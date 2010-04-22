require File.expand_path('../../spec_helper', __FILE__)

describe "environment.rb file" do

  describe "with git gems that don't have gemspecs" do
    before :each do
      build_git "no-gemspec", :gemspec => false

      install_gemfile <<-G
        gem "no-gemspec", "1.0", :git => "#{lib_path('no-gemspec-1.0')}"
      G

      bundle :lock
    end

    it "loads the library via a virtual spec" do
      run <<-R, :lite_runtime => true
        require 'no-gemspec'
        puts NOGEMSPEC
      R

      out.should == "1.0"
    end
  end

  describe "with bundled and system gems" do
    before :each do
      system_gems "rack-1.0.0"

      install_gemfile <<-G
        source "file://#{gem_repo1}"

        gem "activesupport", "2.3.5"
      G

      bundle :lock
    end

    it "does not pull in system gems" do
      run <<-R, :lite_runtime => true
        require 'rubygems'

        begin;
          require 'rack'
        rescue LoadError
          puts 'WIN'
        end
      R

      out.should == "WIN"
    end

    it "provides a gem method" do
      run <<-R, :lite_runtime => true
        gem 'activesupport'
        require 'activesupport'
        puts ACTIVESUPPORT
      R

      out.should == "2.3.5"
    end

    it "raises an exception if gem is used to invoke a system gem not in the bundle" do
      run <<-R, :lite_runtime => true
        begin
          gem 'rack'
        rescue LoadError => e
          puts e.message
        end
      R

      out.should == "rack is not part of the bundle. Add it to Gemfile."
    end

    it "sets GEM_HOME appropriately" do
      run "puts ENV['GEM_HOME']", :lite_runtime => true
      out.should == default_bundle_path.to_s
    end

    it "sets GEM_PATH appropriately" do
      run "puts Gem.path", :lite_runtime => true
      out.should == default_bundle_path.to_s
    end
  end

  describe "with system gems in the bundle" do
    before :each do
      system_gems "rack-1.0.0"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0.0"
        gem "activesupport", "2.3.5"
      G

      bundle :lock
    end

    it "sets GEM_PATH appropriately" do
      run "puts Gem.path", :lite_runtime => true
      paths = out.split("\n")
      paths.should include(system_gem_path.to_s)
      paths.should include(default_bundle_path.to_s)
    end
  end

  describe "with a gemspec that requires other files" do
    before(:each) do
      build_git "bar", :gemspec => false do |s|
        s.write "lib/bar/version.rb", %{BAR_VERSION = '1.0'}
        s.write "bar.gemspec", <<-G
          lib = File.expand_path('../lib/', __FILE__)
          $:.unshift lib unless $:.include?(lib)
          require 'bar/version'

          Gem::Specification.new do |s|
            s.name        = 'bar'
            s.version     = BAR_VERSION
            s.summary     = 'Bar'
            s.files       = Dir["lib/**/*.rb"]
          end
        G
      end

      install_gemfile <<-G
        gem "bar", :git => "#{lib_path('bar-1.0')}"
      G
      bundle :lock
    end

    it "evals each gemspec in the context of its parent directory" do
      run <<-RUBY, :lite_runtime => true
        require 'bar'
        puts BAR
      RUBY
      out.should == "1.0"
    end

    it "error intelligently if the gemspec has a LoadError" do
      update_git "bar", :gemspec => false do |s|
        s.write "bar.gemspec", "require 'doesnotexist'"
      end
      bundle "install --relock"
      out.should include("was a LoadError while evaluating bar.gemspec")
      out.should include("try to require a relative path")
    end

    it "evals each gemspec with a binding from the top level" do
      ruby <<-RUBY
        require 'bundler'
        def Bundler.require(path)
          raise "LOSE"
        end
        Bundler.load
      RUBY
      out.should == ""
    end
  end

  describe "versioning" do
    before :each do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
      bundle :lock
      should_be_locked
    end

    it "loads if current" do
      File.open(env_file, 'a'){|f| f.puts "puts 'using environment.rb'" }
      ruby <<-R
        require "rubygems"
        require "bundler"
        Bundler.setup
      R
      out.should include("using environment.rb")
    end

    it "tells you to install if lock is outdated" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0"
      G
      run "puts 'lockfile current'", :lite_runtime => true, :expect_err => true
      out.should_not include("lockfile current")
      err.should include("Gemfile changed since you last locked.")
      err.should include("Please run `bundle lock` to relock.")
    end

    it "regenerates if from an old bundler" do
      env_file <<-E
        # Generated by Bundler 0.8
        puts "noo"
      E

      ruby <<-R
        require "rubygems"
        require "bundler"
        Bundler.setup
      R
      out.should_not include("noo")
      env_file.read.should include("Generated by Bundler #{Bundler::VERSION}")
    end

    it "warns you if it's from an old bundler but read-only" do
      env_file(env_file.read.gsub("by Bundler #{Bundler::VERSION}", "by Bundler 0.9.0"))
      FileUtils.chmod 0444, env_file
      ruby <<-R, :expect_err => true
        require "rubygems"
        require "bundler"
        Bundler.setup
      R
      err.should include("Cannot write to outdated .bundle/environment.rb")
      FileUtils.rm_rf env_file
    end

    it "requests regeneration if it's out of sync" do
      old_env = File.read(env_file)
      install_gemfile <<-G, :relock => true
        source "file://#{gem_repo1}"
        gem "activesupport"
      G
      should_be_locked

      env_file(old_env)
      run "puts 'fingerprints synced'", :lite_runtime => true, :expect_err => true
      out.should_not include("fingerprints synced")
      err.should include("out of date")
      err.should include("`bundle install`")
    end
  end

  describe "when Bundler is bundled" do
    it "doesn't blow up" do
      install_gemfile <<-G
        gem "bundler", :path => "#{File.expand_path("..", lib)}"
      G
      bundle :lock

      bundle %|exec ruby -e "require 'bundler'; Bundler.setup"|
      err.should be_empty
    end

    it "handles polyglot making Kernel#require public :(" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      ruby <<-RUBY
        require 'rubygems'
        module Kernel
          alias polyglot_original_require require
          def require(*a, &b)
            polyglot_original_require(*a, &b)
          end
        end
        require 'bundler'
        Bundler.require(:foo, :bar)
      RUBY
      err.should be_empty
    end

    it "does not write out env.rb if env.rb has already been loaded" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "bundler", :path => "#{File.expand_path("..", lib)}"
        gem "rake"
      G
      bundle :lock

      FileUtils.chmod 0444, env_file
      run <<-RUBY, :lite_runtime => true
        require 'bundler'
        Bundler.runtime
      RUBY
      env_file.rmtree
    end
  end
end
