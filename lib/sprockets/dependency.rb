module Sprockets
  class Dependency
    # Internal initializer to load `Asset` from serialized `Hash`.
    def self.from_hash(environment, hash)
      return unless hash.is_a?(Hash)

      klass = case hash['class']
        when 'Dependency'
          Dependency
        when 'StaticAsset'
          StaticAsset
        when 'ProcessedAsset'
          ProcessedAsset
        when 'BundledAsset'
          BundledAsset
        else
          nil
        end

      if klass
        asset = klass.allocate
        asset.init_with(environment, hash)
        asset
      end

    # TODO: Think long and hard about this
    rescue Exception
      nil
    end

    attr_reader :pathname, :logical_path, :mtime, :digest

    def initialize(environment, pathname, logical_path)
      @root         = environment.root
      @pathname     = pathname.is_a?(Pathname) ? pathname : Pathname.new(pathname)
      @logical_path = logical_path.to_s
      @mtime        = environment.stat(pathname).mtime
      @digest       = environment.file_digest(pathname).hexdigest
    end

    # Initialize `Asset` from serialized `Hash`.
    def init_with(environment, coder)
      @root = environment.root

      @logical_path = coder['logical_path']
      @digest       = coder['digest']

      if pathname = coder['pathname']
        # Expand `$root` placeholder and wrapper string in a `Pathname`
        @pathname = Pathname.new(expand_root_path(pathname))
      end

      if mtime = coder['mtime']
        # Parse time string
        @mtime = Time.parse(mtime)
      end
    end

    # Copy serialized attributes to the coder object
    def encode_with(coder)
      coder['class']        = self.class.name.sub(/Sprockets::/, '')
      coder['logical_path'] = logical_path
      coder['pathname']     = relativize_root_path(pathname).to_s
      coder['mtime']        = mtime.iso8601
      coder['digest']       = digest
    end

    # Assets are equal if they share the same path, mtime and digest.
    def eql?(other)
      other.is_a?(self.class) &&
        logical_path.eql?(other.logical_path) &&
        mtime.eql?(other.mtime) &&
        digest.eql?(other.digest)
    end
    alias_method :==, :eql?

    def hash
      digest.hash
    end

    # Checks if Dependency is fresh by comparing the actual mtime and
    # digest to the inmemory model.
    #
    # Used to test if cached models need to be rebuilt.
    #
    # `dep` is a `Hash` with `path`, `mtime` and `hexdigest` keys.
    #
    # A `Hash` is used rather than other `Asset` object because we
    # want to test non-asset files and directories.
    def fresh?(environment)
      stat = environment.stat(pathname)

      # If path no longer exists, its definitely stale.
      if stat.nil?
        return false
      end

      # Compare dependency mime to the actual mtime. If the
      # dependency mtime is newer than the actual mtime, the file
      # hasn't changed since we created this `Asset` instance.
      #
      # However, if the mtime is newer it doesn't mean the asset is
      # stale. Many deployment environments may recopy or recheckout
      # assets on each deploy. In this case the mtime would be the
      # time of deploy rather than modified time.
      if self.mtime >= stat.mtime
        return true
      end

      digest = environment.file_digest(pathname)

      # If the mtime is newer, do a full digest comparsion. Return
      # fresh if the digests match.
      if self.digest == digest.hexdigest
        return true
      end

      # Otherwise, its stale.
      false
    end

    # Checks if Asset is stale by comparing the actual mtime and
    # digest to the inmemory model.
    #
    # Subclass must override `fresh?` or `stale?`.
    def stale?(environment)
      !fresh?(environment)
    end

    # Pretty inspect
    def inspect
      "#<#{self.class}:0x#{object_id.to_s(16)} " +
        "pathname=#{pathname.to_s.inspect}, " +
        "mtime=#{mtime.inspect}, " +
        "digest=#{digest.inspect}" +
        ">"
    end

    protected
      # Get pathname with its root stripped.
      def relative_pathname
        @relative_pathname ||= Pathname.new(relativize_root_path(pathname))
      end

      # Replace `$root` placeholder with actual environment root.
      def expand_root_path(path)
        path.to_s.sub(/^\$root/, @root)
      end

      # Replace actual environment root with `$root` placeholder.
      def relativize_root_path(path)
        path.to_s.sub(/^#{Regexp.escape(@root)}/, '$root')
      end
  end
end
