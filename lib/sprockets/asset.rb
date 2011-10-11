require 'time'
require 'set'

module Sprockets
  # `Asset` is the base class for `BundledAsset` and `StaticAsset`.
  class Asset < Dependency
    attr_reader :content_type, :length

    def initialize(environment, logical_path, pathname)
      super(environment, pathname, logical_path)

      @content_type = environment.content_type_of(pathname)
      @length       = environment.stat(pathname).size

      @dependency_paths = []
    end

    # Initialize `Asset` from serialized `Hash`.
    def init_with(environment, coder)
      super

      @dependency_paths = []
      @content_type = coder['content_type']

      if length = coder['length']
        # Convert length to an `Integer`
        @length = Integer(length)
      end
    end

    # Copy serialized attributes to the coder object
    def encode_with(coder)
      super
      coder['content_type'] = content_type
      coder['length']       = length
    end

    # Return logical path with digest spliced in.
    #
    #   "foo/bar-37b51d194a7513e45b56f6524f2d51f2.js"
    #
    def digest_path
      logical_path.sub(/\.(\w+)$/) { |ext| "-#{digest}#{ext}" }
    end

    # Return an `Array` of `Asset` files that are declared dependencies.
    def dependencies
      []
    end

    # TODO: Document this method
    def required_assets
      []
    end

    # Expand asset into an `Array` of parts.
    #
    # Appending all of an assets body parts together should give you
    # the asset's contents as a whole.
    #
    # This allows you to link to individual files for debugging
    # purposes.
    def to_a
      [self]
    end

    # `body` is aliased to source by default if it can't have any dependencies.
    def body
      source
    end

    # Return `String` of concatenated source.
    def to_s
      source
    end

    # Add enumerator to allow `Asset` instances to be used as Rack
    # compatible body objects.
    def each
      yield to_s
    end

    # Save asset to disk.
    def write_to(filename, options = {})
      # Gzip contents if filename has '.gz'
      options[:compress] ||= File.extname(filename) == '.gz'

      File.open("#{filename}+", 'wb') do |f|
        if options[:compress]
          # Run contents through `Zlib`
          gz = Zlib::GzipWriter.new(f, Zlib::BEST_COMPRESSION)
          gz.write to_s
          gz.close
        else
          # Write out as is
          f.write to_s
          f.close
        end
      end

      # Atomic write
      FileUtils.mv("#{filename}+", filename)

      # Set mtime correctly
      File.utime(mtime, mtime, filename)

      nil
    ensure
      # Ensure tmp file gets cleaned up
      FileUtils.rm("#{filename}+") if File.exist?("#{filename}+")
    end

    protected
      # TODO: Document this method
      attr_reader :dependency_paths
  end
end
