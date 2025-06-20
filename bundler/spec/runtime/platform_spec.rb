# frozen_string_literal: true

RSpec.describe "Bundler.setup with multi platform stuff" do
  it "raises a friendly error when gems are missing locally" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    lockfile <<-G
      GEM
        remote: https://gem.repo1/
        specs:
          myrack (1.0)

      PLATFORMS
        #{local_tag}

      DEPENDENCIES
        myrack
    G

    ruby <<-R
      begin
        require 'bundler'
        Bundler.ui.silence { Bundler.setup }
      rescue Bundler::GemNotFound => e
        puts "WIN"
      end
    R

    expect(out).to eq("WIN")
  end

  it "will resolve correctly on the current platform when the lockfile was targeted for a different one" do
    lockfile <<-G
      GEM
        remote: https://gem.repo1/
        specs:
          nokogiri (1.4.2-java)
            weakling (= 0.0.3)
          weakling (0.0.3)

      PLATFORMS
        java

      DEPENDENCIES
        nokogiri
    G

    simulate_platform "x86-darwin-10" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "nokogiri"
      G

      expect(the_bundle).to include_gems "nokogiri 1.4.2"
    end
  end

  it "will keep both platforms when both ruby and a specific ruby platform are locked and the bundle is unlocked" do
    build_repo4 do
      build_gem "nokogiri", "1.11.1" do |s|
        s.add_dependency "mini_portile2", "~> 2.5.0"
        s.add_dependency "racca", "~> 1.5.2"
      end

      build_gem "nokogiri", "1.11.1" do |s|
        s.platform = Bundler.local_platform
        s.add_dependency "racca", "~> 1.4"
      end

      build_gem "mini_portile2", "2.5.0"
      build_gem "racca", "1.5.2"
    end

    checksums = checksums_section do |c|
      c.checksum gem_repo4, "mini_portile2", "2.5.0"
      c.checksum gem_repo4, "nokogiri", "1.11.1"
      c.checksum gem_repo4, "nokogiri", "1.11.1", Bundler.local_platform
      c.checksum gem_repo4, "racca", "1.5.2"
    end

    good_lockfile = <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          mini_portile2 (2.5.0)
          nokogiri (1.11.1)
            mini_portile2 (~> 2.5.0)
            racca (~> 1.5.2)
          nokogiri (1.11.1-#{Bundler.local_platform})
            racca (~> 1.4)
          racca (1.5.2)

      PLATFORMS
        #{lockfile_platforms("ruby")}

      DEPENDENCIES
        nokogiri (~> 1.11)
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L

    gemfile <<-G
      source "https://gem.repo4"
      gem "nokogiri", "~> 1.11"
    G

    lockfile good_lockfile

    bundle "update nokogiri"

    expect(lockfile).to eq(good_lockfile)
  end

  it "will not try to install platform specific gems when they don't match the current ruby if locked only to ruby" do
    build_repo4 do
      build_gem "nokogiri", "1.11.1"

      build_gem "nokogiri", "1.11.1" do |s|
        s.platform = Bundler.local_platform
        s.required_ruby_version = "< #{Gem.ruby_version}"
      end
    end

    gemfile <<-G
      source "https://gem.repo4"
      gem "nokogiri"
    G

    lockfile <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          nokogiri (1.11.1)

      PLATFORMS
        ruby

      DEPENDENCIES
        nokogiri

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install"

    expect(out).to include("Fetching nokogiri 1.11.1")
    expect(the_bundle).to include_gems "nokogiri 1.11.1"
    expect(the_bundle).not_to include_gems "nokogiri 1.11.1 #{Bundler.local_platform}"
  end

  it "will use the java platform if both generic java and generic ruby platforms are locked", :jruby_only do
    gemfile <<-G
      source "https://gem.repo1"
      gem "nokogiri"
    G

    lockfile <<-G
      GEM
        remote: https://gem.repo1/
        specs:
          nokogiri (1.4.2)
          nokogiri (1.4.2-java)
            weakling (>= 0.0.3)
          weakling (0.0.3)

      PLATFORMS
        java
        ruby

      DEPENDENCIES
        nokogiri

      BUNDLED WITH
        #{Bundler::VERSION}
    G

    bundle "install"

    expect(out).to include("Fetching nokogiri 1.4.2 (java)")
    expect(the_bundle).to include_gems "nokogiri 1.4.2 java"
  end

  it "will add the resolve for the current platform" do
    lockfile <<-G
      GEM
        remote: https://gem.repo1/
        specs:
          nokogiri (1.4.2-java)
            weakling (= 0.0.3)
          weakling (0.0.3)

      PLATFORMS
        java

      DEPENDENCIES
        nokogiri
    G

    simulate_platform "x86-darwin-100" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "nokogiri"
        gem "platform_specific"
      G

      expect(the_bundle).to include_gems "nokogiri 1.4.2", "platform_specific 1.0 x86-darwin-100"
    end
  end

  it "allows specifying only-ruby-platform on jruby", :jruby_only do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "nokogiri"
      gem "platform_specific"
    G

    bundle "config set force_ruby_platform true"

    bundle "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2", "platform_specific 1.0 ruby"
  end

  it "allows specifying only-ruby-platform" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "nokogiri"
      gem "platform_specific"
    G

    bundle "config set force_ruby_platform true"

    bundle "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2", "platform_specific 1.0 ruby"
  end

  it "allows specifying only-ruby-platform even if the lockfile is locked to a specific compatible platform" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "nokogiri"
      gem "platform_specific"
    G

    bundle "config set force_ruby_platform true"

    bundle "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2", "platform_specific 1.0 ruby"
  end

  it "doesn't pull platform specific gems on truffleruby", :truffleruby_only do
    install_gemfile <<-G
     source "https://gem.repo1"
     gem "platform_specific"
    G

    expect(the_bundle).to include_gems "platform_specific 1.0 ruby"
  end

  it "doesn't pull platform specific gems on truffleruby (except when whitelisted) even if lockfile was generated with an older version that declared ruby as platform", :truffleruby_only do
    gemfile <<-G
      source "https://gem.repo1"
      gem "platform_specific"
    G

    lockfile <<-L
      GEM
        remote: https://gem.repo1/
        specs:
          platform_specific (1.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        platform_specific

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install"

    expect(the_bundle).to include_gems "platform_specific 1.0 ruby"

    simulate_platform "x86_64-linux" do
      build_repo4 do
        build_gem "libv8"

        build_gem "libv8" do |s|
          s.platform = "x86_64-linux"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "libv8"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo4/
          specs:
            libv8 (1.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          libv8

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "install"

      expect(the_bundle).to include_gems "libv8 1.0 x86_64-linux"
    end
  end

  it "doesn't pull platform specific gems on truffleruby, even if lockfile only includes those", :truffleruby_only do
    gemfile <<-G
      source "https://gem.repo1"
      gem "platform_specific"
    G

    lockfile <<-L
      GEM
        remote: https://gem.repo1/
        specs:
          platform_specific (1.0-x86-darwin-100)

      PLATFORMS
        x86-darwin-100

      DEPENDENCIES
        platform_specific

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install"

    expect(the_bundle).to include_gems "platform_specific 1.0 ruby"
  end

  it "pulls platform specific gems correctly on musl" do
    build_repo4 do
      build_gem "nokogiri", "1.13.8" do |s|
        s.platform = "aarch64-linux"
      end
    end

    simulate_platform "aarch64-linux-musl" do
      install_gemfile <<-G, verbose: true
        source "https://gem.repo4"
        gem "nokogiri"
      G
    end

    expect(out).to include("Fetching nokogiri 1.13.8 (aarch64-linux)")
  end

  it "allows specifying only-ruby-platform on windows with dependency platforms" do
    simulate_platform "x86-mswin32" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "nokogiri", :platforms => [:windows, :jruby]
        gem "platform_specific"
      G

      bundle "config set force_ruby_platform true"

      bundle "install"

      expect(the_bundle).to include_gems "platform_specific 1.0 ruby"
      expect(the_bundle).to not_include_gems "nokogiri"
    end
  end

  it "allows specifying only-ruby-platform on windows with gemspec dependency" do
    build_lib("foo", "1.0", path: bundled_app) do |s|
      s.add_dependency "myrack"
    end

    gemfile <<-G
      source "https://gem.repo1"
      gemspec
    G
    bundle :lock

    simulate_platform "x86-mswin32" do
      bundle "config set force_ruby_platform true"
      bundle "install"

      expect(the_bundle).to include_gems "myrack 1.0"
    end
  end

  it "recovers when the lockfile is missing a platform-specific gem" do
    build_repo2 do
      build_gem "requires_platform_specific" do |s|
        s.add_dependency "platform_specific"
      end
    end
    simulate_platform "x64-mingw-ucrt" do
      lockfile <<-L
        GEM
          remote: https://gem.repo2/
          specs:
            platform_specific (1.0-x86-mingw32)
            requires_platform_specific (1.0)
              platform_specific

        PLATFORMS
          x64-mingw-ucrt
          x86-mingw32

        DEPENDENCIES
          requires_platform_specific
      L

      install_gemfile <<-G, verbose: true
        source "https://gem.repo2"
        gem "requires_platform_specific"
      G

      expect(out).to include("lockfile does not have all gems needed for the current platform")
      expect(the_bundle).to include_gem "platform_specific 1.0 x64-mingw-ucrt"
    end
  end

  %w[x86-mswin32 x64-mswin64 x86-mingw32 x64-mingw-ucrt x64-mingw-ucrt aarch64-mingw-ucrt].each do |platform|
    it "allows specifying platform windows on #{platform} platform" do
      simulate_platform platform do
        lockfile <<-L
          GEM
            remote: https://gem.repo1/
            specs:
              platform_specific (1.0-#{platform})
              requires_platform_specific (1.0)
                platform_specific

          PLATFORMS
            #{platform}

          DEPENDENCIES
            requires_platform_specific
        L

        install_gemfile <<-G
          source "https://gem.repo1"
          gem "platform_specific", :platforms => [:windows]
        G

        expect(the_bundle).to include_gems "platform_specific 1.0 #{platform}"
      end
    end
  end
end
