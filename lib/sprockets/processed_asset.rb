require 'sprockets/asset'
require 'sprockets/utils'
require 'sprockets/dependency'

module Sprockets
  class ProcessedAsset < Asset
    attr_reader :required_assets

    def initialize(environment, logical_path, pathname)
      super

      start_time = Time.now.to_f

      context = environment.context_class.new(environment, logical_path, pathname)
      @source = context.evaluate(pathname)

      # TODO: Move these into there own method

      @required_assets = []
      required_assets_cache = {}
      (context._required_paths + [pathname.to_s]).each do |path|
        if path == self.pathname.to_s
          unless required_assets_cache[self]
            required_assets_cache[self] = true
            @required_assets << self
          end
        elsif asset = environment.find_asset(path, :bundle => false)
          asset.required_assets.each do |asset_dependency|
            unless required_assets_cache[asset_dependency]
              required_assets_cache[asset_dependency] = true
              @required_assets << asset_dependency
            end
          end
        end
      end
      required_assets_cache.clear
      required_assets_cache = nil

      dependency_paths = {}
      context._dependency_paths.each do |path|
        dep = environment.find_dependency(path)
        dependency_paths[dep] = true
      end

      context._dependency_assets.each do |path|
        if path == self.pathname.to_s
          dependency_paths[self] = true
        elsif asset = environment.find_asset(path, :bundle => false)
          asset.dependency_paths.each do |d|
            dependency_paths[d] = true
          end
        end
      end
      @dependency_paths = dependency_paths.keys

      elapsed_time = ((Time.now.to_f - start_time) * 1000).to_i
      environment.logger.info "Compiled #{logical_path}  (#{elapsed_time}ms)  (pid #{Process.pid})"
    end

    attr_reader :source

    # Initialize `BundledAsset` from serialized `Hash`.
    def init_with(environment, coder)
      super

      @source          = coder['source']
      @required_assets = coder['required_paths'].map { |p|
        p = expand_root_path(p)
        p == pathname.to_s ? self : environment.find_asset(p, :bundle => false)
      }
      @dependency_paths = coder['dependency_paths'].map { |asset, p|
        p = expand_root_path(p)
        p == pathname.to_s ? self : (asset ? environment.find_asset(p, :bundle => false) : environment.find_dependency(p))
      }
    end

    # Serialize custom attributes in `BundledAsset`.
    def encode_with(coder)
      super

      coder['source']           = source
      coder['required_paths']   = required_assets.map { |a|
        relativize_root_path(a.pathname).to_s
      }
      coder['dependency_paths'] = dependency_paths.map { |d|
        [d.is_a?(Asset), relativize_root_path(d.pathname).to_s]
      }
    end

    # Checks if Asset is stale by comparing the actual mtime and
    # digest to the inmemory model.
    def fresh?(environment)
      # Check freshness of all declared dependencies
      @dependency_paths.all? { |dep|
        if dep.nil?
          false
        elsif dep.pathname == self.pathname
          super
        else
          dep.fresh?(environment)
        end
      }
    end
  end
end
