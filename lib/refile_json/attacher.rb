module RefileJson
  class Attacher < Refile::Attacher
    def cache_id
      Presence[@metadata[:id]] || read(:id, cache: true)
    end

    def get
      if remove?
        nil
      elsif cache_id
        cache.get(cache_id)
      elsif id
        store.get(id)
      end
    end

    def set(value)
      case value
        when nil then self.remove = true
        when String, Hash then retrieve!(value)
        else cache!(value)
      end
    end

    def cache!(uploadable)
      super
      # cache_id set to json_field
      if @metadata[:id]
        write(:id, @metadata[:id])
        write(:cache, true)
      end
    end

    def download(url)
      super
      # cache_id set to json_field
      if @metadata[:id]
        write(:id, @metadata[:id])
        write(:cache, true)
      end
    end

    def store!
      if remove?
        delete!
        write(:id, nil, true)
        remove_metadata
      elsif cache_id
        file = store.upload(get)
        delete!
        write(:id, file.id, true, true)
        write_metadata
      end
      @metadata = {}
    end

    private

      def read(column, strict = false, cache: false)
        m = "#{name}_json"
        return if !strict && !record.respond_to?(m)

        source = JSON.parse(record.send(m) || "{}")
        value = source[column.to_s]
        return value if column != :id
        # when `cache` true, return if cache key exists.
        # when `cache` false, not return if cache key exists.
        return value unless cache ^ source["cache"]
        nil
      end

      def write(column, value, strict = false, store = false)
        m = "#{name}_json"
        n = "#{m}="
        return if record.frozen?
        return if !strict && !record.respond_to?(n)

        source = JSON.parse(record.send(m) || "{}")
        if value
          source[column.to_s] = value
        else
          source.delete(column.to_s)
        end
        source.delete("cache") if store
        record.send(n, source.to_json)
      end

      def remove_metadata
        write(:size, nil)
        write(:content_type, nil)
        write(:filename, nil)
      end
  end
end
