require "test_helper"

require "shrine"
require "shrine/plugins/uppy_s3_multipart"
require "shrine/storage/s3"
require "shrine/storage/memory"

require "rack"
require "rack/test"

describe Shrine::Plugins::UppyS3Multipart do
  include Rack::Test::Methods

  def s3(**options)
    Shrine::Storage::S3.new(
      bucket: "my-bucket",
      stub_responses: true,
      **options
    )
  end

  def app
    app = Rack::Builder.new
    app.run -> (env) { @app.call(env) }
    app
  end

  def client
    @shrine.storages[:s3].client
  end

  before do
    @shrine = Class.new(Shrine)
    @shrine.storages[:s3] = s3
    @shrine.plugin :uppy_s3_multipart

    @app = @shrine.uppy_s3_multipart(:s3)
  end

  it "returns the app" do
    assert_instance_of Uppy::S3Multipart::App, @shrine.uppy_s3_multipart(:s3)
  end

  it "passes the bucket" do
    post "/multipart"

    assert_equal :create_multipart_upload, client.api_requests[0][:operation_name]
    assert_equal "my-bucket",              client.api_requests[0][:params][:bucket]
  end

  it "passes the prefix" do
    @shrine.storages[:s3] = s3(prefix: "prefix")
    @app = @shrine.uppy_s3_multipart(:s3)

    post "/multipart"

    assert_equal :create_multipart_upload, client.api_requests[0][:operation_name]
    assert_match /^prefix\/\w+$/,          client.api_requests[0][:params][:key]
  end

  it "passes the public" do
    @shrine.storages[:s3] = s3(public: true)
    @app = @shrine.uppy_s3_multipart(:s3)

    post "/multipart"

    assert_equal :create_multipart_upload, client.api_requests[0][:operation_name]
    assert_match "public-read",            client.api_requests[0][:params][:acl]
  end

  it "passes client options" do
    @shrine.plugin :uppy_s3_multipart, options: {
      create_multipart_upload: { acl: "public-read" },
    }
    @app = @shrine.uppy_s3_multipart(:s3)

    post "/multipart"

    assert_equal :create_multipart_upload, client.api_requests[0][:operation_name]
    assert_equal "public-read",            client.api_requests[0][:params][:acl]
  end

  it "allows overriding app options" do
    @app = @shrine.uppy_s3_multipart(:s3, options: { create_multipart_upload: { acl: "public-read" } })
    post "/multipart"

    assert_equal :create_multipart_upload, client.api_requests[0][:operation_name]
    assert_equal "public-read",            client.api_requests[0][:params][:acl]
  end

  it "works for subclass of S3 storage" do
    @shrine.storages[:s3] = Class.new(Shrine::Storage::S3).new(
      bucket:         "my-bucket",
      stub_responses: true,
    )

    @shrine.uppy_s3_multipart(:s3)
  end

  it "fails for non-S3 storage" do
    @shrine.storages[:memory] = Shrine::Storage::Memory.new

    assert_raises(Shrine::Error) { @shrine.uppy_s3_multipart(:memory) }
  end
end
