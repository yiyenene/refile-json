module RefileJson
  module Attachment
    def attachment(name, cache: :cache, store: :store, raise_errors: true, type: nil, extension: nil, content_type: nil)
      definition = Refile::AttachmentDefinition.new(
        name,
        cache: cache,
        store: store,
        raise_errors: raise_errors,
        type: type,
        extension: extension,
        content_type: content_type
      )

      define_singleton_method :"#{name}_attachment_definition" do
        definition
      end

      include create_module(name, definition)
    end

    def attachment_multiple(name, cache: :cache, store: :store, raise_errors: true, type: nil, extension: nil, content_type: nil, append: false)
      definition = Refile::AttachmentDefinition.new(
        name,
        cache: cache,
        store: store,
        raise_errors: raise_errors,
        type: type,
        extension: extension,
        content_type: content_type
      )

      define_singleton_method :"#{name}_attachment_definition" do
        definition
      end

      include create_multiple_module(name, definition, append)
    end

    private

      def create_module(name, definition)
        Module.new do
          attacher = :"#{name}_attacher"

          define_method :"#{name}_attachment_definition" do
            definition
          end

          define_method attacher do
            ivar = :"@#{attacher}"
            instance_variable_get(ivar) || instance_variable_set(ivar, RefileJson::Attacher.new(definition, self))
          end

          define_method "#{name}=" do |value|
            send(attacher).set(value)
          end

          define_method name do
            send(attacher).get
          end

          define_method "remove_#{name}=" do |remove|
            send(attacher).remove = remove
          end

          define_method "remove_#{name}" do
            send(attacher).remove
          end

          define_method "remote_#{name}_url=" do |url|
            send(attacher).download(url)
          end

          define_method "remote_#{name}_url" do
          end

          define_method "#{name}_url" do |*args|
            Refile.attachment_url(self, name, *args)
          end

          define_method "presigned_#{name}_url" do |expires_in = 900|
            attachment = send(attacher)
            attachment.store.object(attachment.id).presigned_url(:get, expires_in: expires_in) unless attachment.id.nil?
          end

          define_method "#{name}_data" do
            send(attacher).data
          end

          define_singleton_method("to_s")    { "Refile::Attachment(#{name})" }
          define_singleton_method("inspect") { "Refile::Attachment(#{name})" }
        end
      end

      def create_multiple_module(name, definition, append)
        json_field = "#{name}_json"
        attacher = :"#{name}_attacher"
        attachment = :"#{name}_attachment"
        parsed = :"parsed_#{name}"
        temp_record_module = :"#{name}_temp_record_module"
        temp_record_class = :"#{name}_temp_record_class"

        Module.new do
          define_singleton_method :klass_methods do
            Module.new do
              define_method temp_record_module do
                ivar = :"@#{temp_record_module}"
                instance_variable_get(ivar) ||
                  instance_variable_set(ivar, create_module(name, definition))
              end

              define_method temp_record_class do
                mod = send(temp_record_module)
                ivar = :"@#{temp_record_class}"
                instance_variable_get(ivar) ||
                  instance_variable_set(ivar, Struct.new(json_field.to_sym) { include mod })
              end
            end
          end

          def self.included(klass)
            klass.extend klass_methods
          end

          define_method :"#{name}_attachment_definition" do
            definition
          end

          define_method parsed do
            Refile.parse_json(send(json_field) || "[]")
          end

          define_method "#{parsed}=" do |value|
            send("#{json_field}=", value.to_json)
          end

          # returns instant attachment
          define_method attachment do |value = "{}"|
            self.class.send(temp_record_class).new(value)
          end

          define_method :"#{name}_data" do
            records = send(name)
            if records.all? { |record| record.send(attacher).valid? }
              records.map(&:"#{name}_data").select(&:present?)
            end
          end

          # returns instant attachment array with stored json value
          define_method :"#{name}" do
            send(parsed).map { |x| send(attachment, x.to_json) }
          end

          define_method :"#{name}=" do |files|
            cache, files = files.partition { |file| file.is_a?(String) }

            cache = Refile.parse_json(cache.first)

            if !append && (files.present? || cache.present?)
              send("#{parsed}=", [])
            end

            appends = if files.empty? && cache.present?
                        cache.select(&:present?).map do |file|
                          a = send(attachment)
                          a.send("#{name}=", file.to_json)
                          Refile.parse_json(a.send(json_field))
                        end
                      else
                        files.select(&:present?).map do |file|
                          a = send(attachment)
                          a.send("#{name}=", file)
                          Refile.parse_json(a.send(json_field))
                        end
                      end
            result = send(parsed).concat(appends)
            send("#{parsed}=", result)
          end

          define_method :"#{name}_store!" do
            result = send(name).map do |a|
              a.send(attacher).store!
              Refile.parse_json(a.send(json_field))
            end
            send("#{parsed}=", result)
          end

          define_method :"#{name}_delete!" do
            send(name).each { |x| x.send(attacher).delete! }
          end
        end
      end
  end
end
