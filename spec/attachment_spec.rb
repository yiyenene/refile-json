require "spec_helper"

RSpec.describe RefileJson::Attachment do
  let(:options) { {} }
  let(:klass) do
    opts = options
    Class.new do
      extend RefileJson::Attachment

      attr_accessor :document_json

      attachment :document, **opts
    end
  end
  let(:instance) { klass.new }

  describe ":name=" do
    it "receives a file, caches it and sets the _id parameter" do
      instance.document = Refile::FileDouble.new("hello", "foo.txt", content_type: "text/plain")

      expect(instance.document.read).to eq("hello")

      expect(instance.document_attacher.data[:filename]).to eq("foo.txt")
      expect(instance.document_attacher.data[:size]).to eq(5)
      expect(instance.document_attacher.data[:content_type]).to eq("text/plain")
    end

    it "receives serialized data and retrieves file from it" do
      file = Refile.cache.upload(Refile::FileDouble.new("hello"))
      instance.document = { id: file.id, filename: "foo.txt", content_type: "text/plain", size: 5 }.to_json

      expect(instance.document.read).to eq("hello")

      expect(instance.document_attacher.data[:filename]).to eq("foo.txt")
      expect(instance.document_attacher.data[:size]).to eq(5)
      expect(instance.document_attacher.data[:content_type]).to eq("text/plain")
    end

    it "receives parsed data and retrieves file from it" do
      file = Refile.cache.upload(Refile::FileDouble.new("hello"))
      instance.document = { id: file.id, filename: "foo.txt", content_type: "text/plain", size: 5 }

      expect(instance.document.read).to eq("hello")

      expect(instance.document_attacher.data[:filename]).to eq("foo.txt")
      expect(instance.document_attacher.data[:size]).to eq(5)
      expect(instance.document_attacher.data[:content_type]).to eq("text/plain")
    end

    it "does nothing when assigned string lacks an id" do
      instance.document = { size: 5 }.to_json

      expect(instance.document).to be_nil
    end

    it "does nothing when assigned string is not valid JSON" do
      instance.document = "size:f{oo}"

      expect(instance.document).to be_nil
    end

    it "accepts nil" do
      instance.document = nil
      expect(instance.document).to be_nil
    end

    it "removes a document when assigned nil" do
      instance.document = Refile::FileDouble.new("hello", "foo.txt", content_type: "text/plain")
      instance.document = nil
      expect(instance.document).to be_nil
    end
  end

  describe ":name" do
    it "gets a file from the store" do
      file = Refile.store.upload(Refile::FileDouble.new("hello"))
      instance.document_json = { id: file.id }.to_json

      expect(instance.document.id).to eq(file.id)
    end

    it "complains when `json` attribute not readable" do
      klass.class_eval do
        undef :document_json
      end

      expect do
        instance.document
      end.to raise_error(NoMethodError)
    end
  end

  describe ":url" do
    it "generates URL with extra options" do
      allow(Refile).to receive(:token).and_return("token")

      file = Refile.store.upload(Refile::FileDouble.new("hello"))
      instance.document_json = { id: file.id }.to_json

      expect(instance.document_url("fill", 800, 800)).to eq("http://localhost:56120/attachments/token/store/fill/800/800/#{file.id}/document")
    end
  end

  describe "remote_:name_url=" do
    it "does nothing when nil is assigned" do
      instance.remote_document_url = nil
      expect(instance.document).to be_nil
    end

    it "does nothing when empty string is assigned" do
      instance.remote_document_url = nil
      expect(instance.document).to be_nil
    end
  end

  describe ":name_attacher.store!" do
    it "puts a cached file into the store" do
      instance.document = Refile::FileDouble.new("hello")
      cache = instance.document

      instance.document_attacher.store!

      stored = JSON.parse(instance.document_json)
      expect(Refile.store.get(stored["id"]).read).to eq("hello")
      expect(Refile.store.get(instance.document.id).read).to eq("hello")

      expect(instance.document.read).to eq("hello")
      expect(stored["size"]).to eq(5)

      expect(Refile.cache.get(cache.id).exists?).to be_falsy
    end

    it "complains when `id` attribute not writable" do
      instance.document = Refile::FileDouble.new("hello")

      klass.class_eval do
        undef :document_json=
      end

      expect do
        instance.document_attacher.store!
      end.to raise_error(NoMethodError)
    end

    it "does nothing when not cached" do
      file = Refile.store.upload(Refile::FileDouble.new("hello"))
      instance.document_json = { id: file.id }.to_json

      instance.document_attacher.store!

      stored = JSON.parse(instance.document_json)
      expect(Refile.store.get(stored["id"]).read).to eq("hello")
      expect(Refile.store.get(instance.document.id).read).to eq("hello")
    end

    xit "overwrites previously stored file" do
      file = Refile.store.upload(Refile::FileDouble.new("hello"))
      instance.document_json = { id: file.id }.to_json

      instance.document = Refile::FileDouble.new("world")
      cache = instance.document

      instance.document_attacher.store!

      expect(Refile.store.get(instance.document.id).read).to eq("world")

      expect(instance.document.read).to eq("world")
      expect(Refile.cache.get(cache.id).exists?).to be_falsy
      expect(Refile.store.get(file.id).exists?).to be_falsy
    end

    it "removes an uploaded file when remove? returns true" do
      file = Refile.store.upload(Refile::FileDouble.new("hello"))
      instance.document_json = { id: file.id }.to_json

      instance.document_attacher.remove = true
      instance.document_attacher.store!

      # expect(instance.document_id).to be_nil
      expect(Refile.store.exists?(file.id)).to be_falsy
    end

    it "removes metadata when remove? returns true" do
      file = Refile.store.upload(Refile::FileDouble.new("hello"))
      instance.document_json = {
        id: file.id,
        size: file.size,
        filename: "foo",
        content_type: "bar"
      }.to_json

      instance.document_attacher.remove = true
      instance.document_attacher.store!

      stored = JSON.parse(instance.document_json)

      expect(stored["id"]).to be_nil
      expect(stored["size"]).to be_nil
      expect(stored["filename"]).to be_nil
      expect(stored["content_type"]).to be_nil
    end
  end

  describe ":name_attacher.delete!" do
    it "deletes a stored file" do
      instance.document = Refile::FileDouble.new("hello")
      instance.document_attacher.store!
      file = instance.document

      instance.document_attacher.delete!

      expect(Refile.store.exists?(file.id)).to be_falsy
    end

    it "deletes a cached file" do
      instance.document = Refile::FileDouble.new("hello")
      file = instance.document

      instance.document_attacher.delete!

      expect(Refile.cache.exists?(file.id)).to be_falsy
    end
  end

  describe ":name_attacher.remove?" do
    it "should be true when the value is truthy" do
      instance.document_attacher.remove = true
      expect(instance.document_attacher.remove?).to be_truthy
    end

    it "should be false when the value is falsey" do
      instance.document_attacher.remove = false
      expect(instance.document_attacher.remove?).to be_falsy
    end

    it "should be false when the value is ''" do
      instance.document_attacher.remove = ""
      expect(instance.document_attacher.remove?).to be_falsy
    end

    it "should be false when the value is '0'" do
      instance.document_attacher.remove = "0"
      expect(instance.document_attacher.remove?).to be_falsy
    end

    it "should be false when the value is 'false'" do
      instance.document_attacher.remove = "false"
      expect(instance.document_attacher.remove?).to be_falsy
    end
  end

  describe ":name_attacher.valid?" do
    let(:options) { { type: :image, raise_errors: false } }

    it "returns false if no file is attached" do
      expect(instance.document_attacher.valid?).to be_falsy
    end

    it "returns false and if valid file is attached" do
      file = Refile::FileDouble.new("hello", content_type: "image/png")

      instance.document = file

      expect(instance.document_attacher.valid?).to be_truthy
    end

    it "returns false and sets errors if invalid file is attached" do
      file = Refile::FileDouble.new("hello", content_type: "text/plain")

      instance.document = file

      expect(instance.document_attacher.valid?).to be_falsy
      expect(instance.document_attacher.errors).to eq([:invalid_content_type])
    end
  end

  describe ":name_attacher.extension" do
    it "is nil when not inferrable" do
      file = Refile::FileDouble.new("hello")
      instance.document = file
      expect(instance.document_attacher.extension).to be_nil
    end

    it "is inferred from the filename" do
      file = Refile::FileDouble.new("hello", "hello.txt")
      instance.document = file
      expect(instance.document_attacher.extension).to eq("txt")
    end

    it "is inferred from the content type" do
      file = Refile::FileDouble.new("hello", content_type: "image/png")
      instance.document = file
      expect(instance.document_attacher.extension).to eq("png")
    end

    it "returns nil with unknown content type" do
      file = Refile::FileDouble.new("hello", content_type: "foo/doesnotexist")
      instance.document = file
      expect(instance.document_attacher.extension).to be_nil
    end

    it "is nil when filename has no extension" do
      file = Refile::FileDouble.new("hello", "hello")
      instance.document = file
      expect(instance.document_attacher.extension).to be_nil
    end
  end

  describe ":name_attacher.basename" do
    it "is nil when not inferrable" do
      file = Refile::FileDouble.new("hello")
      instance.document = file
      expect(instance.document_attacher.basename).to be_nil
    end

    it "is inferred from the filename" do
      file = Refile::FileDouble.new("hello", "hello.txt")
      instance.document = file
      expect(instance.document_attacher.basename).to eq("hello")
    end

    it "returns filename if filename has no extension" do
      file = Refile::FileDouble.new("hello", "hello")
      instance.document = file
      expect(instance.document_attacher.basename).to eq("hello")
    end
  end

  describe ":name_attacher.error" do
    let(:options) { { cache: :limited_cache, raise_errors: false } }

    it "is blank when valid file uploaded" do
      file = Refile::FileDouble.new("hello")
      instance.document = file

      expect(instance.document_attacher.errors).to be_empty
      expect(Refile.cache.get(instance.document.id).exists?).to be_truthy
    end

    it "contains a list of errors when invalid file uploaded" do
      file = Refile::FileDouble.new("a" * 120)
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:too_large])
      expect(instance.document).to be_nil
    end

    it "is reset when valid file uploaded" do
      file = Refile::FileDouble.new("a" * 120)
      instance.document = file

      file = Refile::FileDouble.new("hello")
      instance.document = file

      expect(instance.document_attacher.errors).to be_empty
      expect(Refile.cache.get(instance.document.id).exists?).to be_truthy
    end
  end

  describe ":name_definition.accept" do
    context "with `extension`" do
      let(:options) { { extension: %w[jpg png] } }

      it "returns an accept string" do
        expect(instance.document_attachment_definition.accept).to eq(".jpg,.png")
      end
    end

    context "with `content_type`" do
      let(:options) { { content_type: %w[image/jpeg image/png], extension: "zip" } }

      it "returns an accept string" do
        expect(instance.document_attachment_definition.accept).to eq("image/jpeg,image/png")
      end
    end
  end

  describe "with option `raise_errors: true" do
    let(:options) { { cache: :limited_cache, raise_errors: true } }

    it "raises an error when invalid file assigned" do
      file = Refile::FileDouble.new("a" * 120)
      expect do
        instance.document = file
      end.to raise_error(Refile::Invalid)

      expect(instance.document_attacher.errors).to eq([:too_large])
      expect(instance.document).to be_nil
    end
  end

  describe "with option `raise_errors: false" do
    let(:options) { { cache: :limited_cache, raise_errors: false } }

    it "does not raise an error when invalid file assigned" do
      file = Refile::FileDouble.new("a" * 120)
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:too_large])
      expect(instance.document).to be_nil
    end
  end

  describe "with option `extension`: %w[txt]`" do
    let(:options) { { extension: "txt", raise_errors: false } }

    it "allows file with correct extension to be uploaded" do
      file = Refile::FileDouble.new("hello", "hello.txt")
      instance.document = file

      expect(instance.document_attacher.errors).to be_empty
      expect(Refile.cache.get(instance.document.id).exists?).to be_truthy
    end

    it "sets error when file with other extension is uploaded" do
      file = Refile::FileDouble.new("hello", "hello.php")
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:invalid_extension])
      expect(instance.document).to be_nil
    end

    it "sets error when file with no extension is uploaded" do
      file = Refile::FileDouble.new("hello")
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:invalid_extension])
      expect(instance.document).to be_nil
    end
  end

  describe "with option `content_type: %w[txt]`" do
    let(:options) { { content_type: "text/plain", raise_errors: false } }

    it "allows file with correct content type to be uploaded" do
      file = Refile::FileDouble.new("hello", content_type: "text/plain")
      instance.document = file

      expect(instance.document_attacher.errors).to be_empty
      expect(Refile.cache.get(instance.document.id).exists?).to be_truthy
    end

    it "sets error when file with other content type is uploaded" do
      file = Refile::FileDouble.new("hello", content_type: "application/php")
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:invalid_content_type])
      expect(instance.document).to be_nil
    end

    it "sets error when file with no content type is uploaded" do
      file = Refile::FileDouble.new("hello")
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:invalid_content_type])
      expect(instance.document).to be_nil
    end
  end

  describe "with option `type: :image`" do
    let(:options) { { type: :image, raise_errors: false } }

    it "allows image to be uploaded" do
      file = Refile::FileDouble.new("hello", content_type: "image/jpeg")
      instance.document = file

      expect(instance.document_attacher.errors).to be_empty
      expect(Refile.cache.get(instance.document.id).exists?).to be_truthy
    end

    it "sets error when file with other content type is uploaded" do
      file = Refile::FileDouble.new("hello", content_type: "application/php")
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:invalid_content_type])
      expect(instance.document).to be_nil
    end

    it "sets error when file with no content type is uploaded" do
      file = Refile::FileDouble.new("hello")
      instance.document = file

      expect(instance.document_attacher.errors).to eq([:invalid_content_type])
      expect(instance.document).to be_nil
    end
  end

  it "includes the module with methods in an instrospectable way" do
    expect { puts klass.ancestors }
      .to output(/Refile::Attachment\(document\)/).to_stdout
    expect { p klass.ancestors }
      .to output(/Refile::Attachment\(document\)/).to_stdout
  end
end
