require 'spec_helper'

describe CachedJSON do
  it "has a version" do
    CachedJSON::VERSION.should_not be_nil
    CachedJSON::VERSION.to_f.should > 0
  end
  context "with basic fields defined for export with json_fields" do
    it "allows subsets of fields to be returned by varying the properties definition" do
      example = JsonFoobar.create({ :foo => "FOO", :baz => "BAZ", :bar => "BAR" })
      # :short is a subset of the fields in :public and :public is a subset of the fields in :all
      example.as_json({ :properties => :short }).should == { :foo => "FOO", "Baz" => "BAZ", :default_foo => "DEFAULT_FOO"}
      example.as_json({ :properties => :public }).should == { :foo => "FOO", "Baz" => "BAZ", :bar => "BAR", :default_foo => "DEFAULT_FOO"}
      example.as_json({ :properties => :all }).should == { :foo => "FOO", :bar => "BAR", "Baz" => "BAZ", :renamed_baz => "BAZ", :default_foo => "DEFAULT_FOO", :computed_field => "FOOBAR" }
    end
    it "throws an error if you ask for an undefined property type" do
      lambda { JsonFoobar.create.as_json({ :properties => :special }) }.should raise_error(ArgumentError)
    end
    it "throws an error if you don't specify properties" do
      lambda { JsonFoobar.create.as_json({ }) }.should raise_error(ArgumentError)
    end
    it "should hit the cache for subsequent as_json calls after the first" do
      foobar = JsonFoobar.create({ :foo => "FOO", :bar => "BAR", :baz => "BAZ" })
      all_result = foobar.as_json({ :properties => :all })
      public_result = foobar.as_json({ :properties => :public })
      short_result = foobar.as_json({ :properties => :short })
      all_result.should_not == public_result
      all_result.should_not == short_result
      public_result.should_not == short_result
      3.times { foobar.as_json({ :properties => :all }).should == all_result }
      3.times { foobar.as_json({ :properties => :public }).should == public_result }
      3.times { foobar.as_json({ :properties => :short }).should == short_result }
    end
    it "should remove values from the cache when a model is saved" do
      foobar = JsonFoobar.create(:foo => "FOO", :bar => "BAR", :baz => "BAZ")
      all_result = foobar.as_json({ :properties => :all })
      public_result = foobar.as_json({ :properties => :public })
      short_result = foobar.as_json({ :properties => :short })
      foobar.foo = "foo"
      # Not saved yet, so we should still be hitting the cache
      3.times { foobar.as_json({ :properties => :all }).should == all_result }
      3.times { foobar.as_json({ :properties => :public }).should == public_result }
      3.times { foobar.as_json({ :properties => :short }).should == short_result }
      foobar.save
      3.times { foobar.as_json({ :properties => :all }).should == all_result.merge({ :foo => "foo", :computed_field => "fooBAR" }) }
      3.times { foobar.as_json({ :properties => :public }).should == public_result.merge({ :foo => "foo" }) }
      3.times { foobar.as_json({ :properties => :short }).should == short_result.merge({ :foo => "foo" }) }
    end
    context "sanitizing fields" do
      before(:each) do
        @dirty_content = "<strong>Content</strong>"
        @dirty_example = DirtyJsonFoobar.new({ :dirty_foo => @dirty_content, :ignored_foo => @dirty_content })
      end
      it "sanitizes JSON fields if :markdown == true" do
        @dirty_example.as_json({ :properties => :public })[:dirty_foo].should == "**Content**"
      end
      it "leaves fields alone by default" do
        @dirty_example.as_json({ :properties => :public })[:ignored_foo].should == @dirty_content
      end
      it "doesn't choke on nil fields" do
        @dirty_example.dirty_foo = nil
        @dirty_example.as_json({ :properties => :public })[:dirty_foo].should == ""
      end
    end
  end
  context "many-to-one relationships" do
    it "uses the correct properties on the base object and passes :short or :all as appropriate" do
      manager = JsonManager.create({ :name => "Boss" })
      peon = manager.json_employees.create({ :name => "Peon" })
      manager.json_employees.create({ :name => "Indentured servant" })
      manager.json_employees.create({ :name => "Serf", :nickname => "Vince" })
      3.times do
        3.times do
          manager_short_json = manager.as_json({ :properties => :short })
          manager_short_json.length.should == 2
          manager_short_json[:name].should == "Boss"
          manager_short_json[:employees].member?({ :name => "Peon" }).should be_true
          manager_short_json[:employees].member?({ :name => "Indentured servant" }).should be_true
          manager_short_json[:employees].member?({ :name => "Serf" }).should be_true
          manager_short_json[:employees].member?({ :nickname => "Serf" }).should be_false
        end
        3.times do
          manager_public_json = manager.as_json({ :properties => :public })
          manager_public_json.length.should == 2
          manager_public_json[:name].should == "Boss"
          manager_public_json[:employees].member?({ :name => "Peon" }).should be_true
          manager_public_json[:employees].member?({ :name => "Indentured servant" }).should be_true
          manager_public_json[:employees].member?({ :name => "Serf" }).should be_true
          manager_public_json[:employees].member?({ :nickname => "Serf" }).should be_false
        end
        3.times do
          manager_all_json = manager.as_json({ :properties => :all })
          manager_all_json.length.should == 3
          manager_all_json[:name].should == "Boss"
          manager_all_json[:ssn].should == "123-45-6789"
          manager_all_json[:employees].member?({ :name => "Peon", :nickname => "My Favorite" }).should be_true
          manager_all_json[:employees].member?({ :name => "Indentured servant", :nickname => "My Favorite" }).should be_true
          manager_all_json[:employees].member?({ :name => "Serf", :nickname => "Vince" }).should be_true
        end
        3.times do
          peon.as_json({ :properties => :short }).should == { :name => "Peon" }
        end
        3.times do
          peon.as_json({ :properties => :all }).should == { :name => "Peon", :nickname => "My Favorite" }
        end
      end
    end
    it "correctly updates fields when either the parent or child class changes" do
      manager = JsonManager.create({ :name => "JsonManager" })
      employee = manager.json_employees.create({ :name => "JsonEmployee" })
      3.times do
        manager.as_json({ :properties => :short }).should == { :name => "JsonManager", :employees => [ { :name => "JsonEmployee" } ] }
        employee.as_json({ :properties => :short }).should == { :name => "JsonEmployee" }
      end
      manager.name = "New JsonManager"
      manager.save
      3.times { manager.as_json({ :properties => :short }).should == { :name => "New JsonManager", :employees => [ { :name => "JsonEmployee" } ] } }
      employee.name = "New JsonEmployee"
      employee.save
      3.times { manager.as_json({ :properties => :short }).should == { :name => "New JsonManager", :employees => [ { :name => "New JsonEmployee" } ] } }
    end
  end
  context "one-to-one relationships" do
    before(:each) do
      @artwork = AwesomeArtwork.create({ :name => "Mona Lisa" })
      @image = @artwork.create_awesome_image({ :name => "Picture of Mona Lisa" })
    end
    it "uses the correct properties on the base object and passes :short to any sub-objects for :public and :short properties" do
      3.times do
        @artwork.as_json({ :properties => :short }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Mona" } }
        @artwork.as_json({ :properties => :public }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Mona" } }
        @artwork.as_json({ :properties => :all }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Mona", :url => "http://example.com/404.html" } }
        @image.as_json({ :properties => :short }).should == { :name => "Picture of Mona Lisa", :nickname => "Mona" }
        @image.as_json({ :properties => :public }).should == { :name => "Picture of Mona Lisa", :nickname => "Mona", :url => "http://example.com/404.html" }
      end
    end
    it "uses the correct properties on the base object and passes :all to any sub-objects for :all properties" do
      3.times do
        @artwork.as_json({ :properties => :all }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Mona", :url => "http://example.com/404.html" } }
      end
    end
    it "correctly updates fields when either the parent or child class changes" do
      # Call as_json for all properties so that the json will get cached
      [:short, :public, :all].each { |properties| @artwork.as_json({ :properties => properties }) }
      @image.nickname = "Worst Painting Ever"
      # Nothing has been saved yet, cached json for referenced document should reflect the truth in the database
      3.times do
        @artwork.as_json({ :properties => :short }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Mona" } }
        @artwork.as_json({ :properties => :public }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Mona" } }
        @artwork.as_json({ :properties => :all }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Mona", :url => "http://example.com/404.html" } }
      end
      @image.save
      3.times do
        @artwork.as_json({ :properties => :short }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Worst Painting Ever" } }
        @artwork.as_json({ :properties => :public }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Worst Painting Ever" } }
        @artwork.as_json({ :properties => :all }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Worst Painting Ever", :url => "http://example.com/404.html" } }
      end
      @image.name = "Picture of Mona Lisa Watercolor"
      3.times do
        @artwork.as_json({ :properties => :short }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Worst Painting Ever" } }
        @artwork.as_json({ :properties => :public }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Worst Painting Ever" } }
        @artwork.as_json({ :properties => :all }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa", :nickname => "Worst Painting Ever", :url => "http://example.com/404.html" } }
      end
      @image.save
      3.times do
        @artwork.as_json({ :properties => :short }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa Watercolor", :nickname => "Worst Painting Ever" } }
        @artwork.as_json({ :properties => :public }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa Watercolor", :nickname => "Worst Painting Ever" } }
        @artwork.as_json({ :properties => :all }).should == { :name => "Mona Lisa", :image => { :name => "Picture of Mona Lisa Watercolor", :nickname => "Worst Painting Ever", :url => "http://example.com/404.html" } }
      end
    end
  end

  context "with a hide_as_child_json_when definition" do
    it "should yield JSON when as_json is called directly and hide_as_child_json_when returns false on an instance" do
      c = SometimesSecret.create({ :should_tell_secret => true })
      c.as_json({ :properties => :short }).should == { :secret => "Afraid of the dark" }
    end
    it "should yield JSON when as_json is called directly and hide_as_child_json_when returns true on an instance" do
      c = SometimesSecret.create({ :should_tell_secret => false })
      c.as_json({ :properties => :short }).should == { :secret => "Afraid of the dark" }
    end
    it "should yield child JSON when as_json is called on the parent and hide_as_child_json_when returns false on an instance" do
      p = SecretParent.create({ :name => "Parent" })
      p.create_sometimes_secret({ :should_tell_secret => true })
      p.as_json({ :properties => :short })[:child].should == { :secret => "Afraid of the dark" }
    end
    it "should not yield child JSON when as_json is called on the parent and hide_as_child_json_when returns true on an instance" do
      p = SecretParent.create({ :name => "Parent" })
      p.create_sometimes_secret({ :should_tell_secret => false })
      p.as_json({ :properties => :short })[:child].should be_nil
    end
  end
  context "relationships with a multi-level hierarchy" do
    before(:each) do
      @artwork = FastJsonArtwork.create
      @image = @artwork.create_fast_json_image
      @url1 = @image.fast_json_urls.create
      @url2 = @image.fast_json_urls.create
      @url3 = @image.fast_json_urls.create
      @common_url = @url1.url
    end
    it "uses the correct properties on the base object and passes :short to any sub-objects for :short and :public" do
      3.times do
        @artwork.as_json({ :properties => :short }).should == {
          :name => "Artwork",
          :image => { :name => "Image",
            :urls => [
              { :url => @common_url },
              { :url => @common_url },
              { :url => @common_url }
            ]
          }
        }
        @artwork.as_json({ :properties => :public }).should == {
          :name => "Artwork",
          :display_name => "Awesome Artwork",
          :image => { :name => "Image",
            :urls => [
              { :url => @common_url },
              { :url => @common_url },
              { :url => @common_url }
            ]
          }
        }
      end
    end
    it "uses the correct properties on the base object and passes :all to any sub-objects for :all" do
      3.times do
        @artwork.as_json({ :properties => :all }).should == {
          :name => "Artwork",
          :display_name => "Awesome Artwork",
          :price => 1000,
          :image => { :name => "Image",
            :urls => [
              { :url => @common_url, :is_public => false },
              { :url => @common_url, :is_public => false },
              { :url => @common_url, :is_public => false } ]
            }
        }
      end
    end
    it "correctly updates json for all classes in the hierarchy when saves occur" do
      # Call as_json once to make sure the json is cached before we modify the referenced model locally
      @artwork.as_json({ :properties => :short })
      new_url = "http://chee.sy/omg.jpg"
      @url1.url = new_url
      # No save has happened, so as_json shouldn't update yet
      3.times do
        @artwork.as_json({ :properties => :short }).should == {
          :name => "Artwork",
          :image => { :name => "Image",
            :urls => [
              { :url => @common_url },
              { :url => @common_url },
              { :url => @common_url }
            ]
          }
        }
      end
      @url1.save
      3.times do
        json = @artwork.as_json
        json[:name].should == "Artwork"
        json[:image][:name].should == "Image"
        json[:image][:urls].map{ |u| u[:url] }.sort.should == [@common_url, @common_url, new_url].sort
      end
    end
  end
end
