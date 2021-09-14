require "test_helper"
require "aws-sdk-s3"
require "rack/test_app"

describe Uppy::S3Multipart::App do
  def app
    app = Rack::Builder.new
    app.use Rack::Lint
    app.run Rack::URLMap.new("/s3/multipart" => @endpoint)

    Rack::TestApp.wrap(app)
  end

  before do
    resource = Aws::S3::Resource.new(stub_responses: true)
    @bucket  = resource.bucket("my-bucket")

    @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket)
    @s3       = @bucket.client
  end

  describe "POST /s3/multipart" do
    it "creates a multipart upload" do
      response = app.post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_match /^\w{32}$/,               @s3.api_requests[0][:params][:key]
    end

    it "returns multipart upload id and key" do
      @s3.stub_responses(:create_multipart_upload, { upload_id: "foo", key: "bar" })

      response = app.post "/s3/multipart"

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "foo",      response.body_json["uploadId"]
      assert_match /^\w{32}$/, response.body_json["key"]
    end

    it "handles 'type' JSON body parameter" do
      response = app.post "/s3/multipart", json: { type: "text/plain" }

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "text/plain",             @s3.api_requests[0][:params][:content_type]
    end

    it "handles 'filename' JSON body parameter" do
      response = app.post "/s3/multipart", json: { filename: "nature.jpg" }

      expected_content_disposition = %(inline; filename="nature.jpg"; filename*=UTF-8''nature.jpg)

      assert_equal :create_multipart_upload,     @s3.api_requests[0][:operation_name]
      assert_equal expected_content_disposition, @s3.api_requests[0][:params][:content_disposition]

      assert_match /^\w{32}\.jpg$/, response.body_json["key"]
    end

    it "handles :prefix option" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, prefix: "prefix")

      response = app.post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_match /^prefix\/\w{32}/,        @s3.api_requests[0][:params][:key]

      assert_match /^prefix\/\w{32}$/, response.body_json["key"]
    end

    it "handles :public option" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, public: true)

      response = app.post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "public-read",            @s3.api_requests[0][:params][:acl]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        create_multipart_upload: { acl: "public-read" }
      })

      response = app.post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "public-read",            @s3.api_requests[0][:params][:acl]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        create_multipart_upload: -> (request) {
          assert_kind_of Rack::Request, request
          { acl: "public-read" }
        }
      })

      response = app.post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "public-read",            @s3.api_requests[0][:params][:acl]
    end

    it "works with a trailing slash (for Rails)" do
      response = app.post "/s3/multipart/"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_match /^\w{32}$/,               @s3.api_requests[0][:params][:key]
    end
  end

  describe "OPTIONS /s3/multipart/:uploadId/:partNumber" do
    it "returns an empty response" do
      response = app.options "/s3/multipart/foo/1"

      assert_equal 204,      response.status
      assert_equal Hash.new, response.headers
      assert_equal "",       response.body_binary
    end
  end

  describe "OPTIONS /s3/multipart" do
    it "returns an empty response" do
      response = app.options "/s3/multipart"

      assert_equal 204,      response.status
      assert_equal Hash.new, response.headers
      assert_equal "",       response.body_binary
    end
  end

  describe "GET /s3/multipart/:uploadId" do
    it "fetches multipart parts" do
      response = app.get "/s3/multipart/foo", query: { key: "bar" }

      assert_equal :list_parts, @s3.api_requests[0][:operation_name]
      assert_equal "foo",       @s3.api_requests[0][:params][:upload_id]
      assert_equal "bar",       @s3.api_requests[0][:params][:key]
    end

    it "returns multipart parts" do
      @s3.stub_responses(:list_parts, { parts: [ { part_number: 1, size: 123, etag: "etag1" } ] })

      response = app.get "/s3/multipart/foo", query: { key: "bar" }

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal 1,       response.body_json[0]["PartNumber"]
      assert_equal 123,     response.body_json[0]["Size"]
      assert_equal "etag1", response.body_json[0]["ETag"]
    end

    it "returns error response when 'key' parameter is missing" do
      response = app.get "/s3/multipart/foo"

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", response.body_json["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        list_parts: { max_parts: 5 }
      })

      response = app.get "/s3/multipart/foo", query: { key: "bar" }

      assert_equal :list_parts,   @s3.api_requests[0][:operation_name]
      assert_equal 5,             @s3.api_requests[0][:params][:max_parts]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        list_parts: -> (request) {
          assert_kind_of Rack::Request, request
          { max_parts: 5 }
        }
      })

      response = app.get "/s3/multipart/foo", query: { key: "bar" }

      assert_equal :list_parts,   @s3.api_requests[0][:operation_name]
      assert_equal 5,             @s3.api_requests[0][:params][:max_parts]
    end
  end

  describe "GET /s3/multipart/:uploadId/batch" do
    it "returns presigned urls for batch part upload" do
      response = app.get "/s3/multipart/foo/batch", query: { key: "bar", partNumbers: "1,2" }

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_match URI.regexp, response.body_json["presignedUrls"]["1"]
      assert_match URI.regexp, response.body_json["presignedUrls"]["2"]
    end

    it "returns error response when 'key' parameter is missing" do
      response = app.get "/s3/multipart/foo/batch", query: { partNumbers: "1,2" }

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", response.body_json["error"]
    end

    it "returns error response when 'partNumbers' parameter is missing" do
      response = app.get "/s3/multipart/foo/batch", query: { key: "bar" }

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Missing \"partNumbers\" parameter", response.body_json["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: { expires_in: 10 }
      })

      response = app.get "/s3/multipart/foo/batch", query: { key: "bar", partNumbers: "1,2" }

      assert_match "X-Amz-Expires=10", response.body_json["presignedUrls"]["1"]
      assert_match "X-Amz-Expires=10", response.body_json["presignedUrls"]["2"]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: -> (request) {
          assert_kind_of Rack::Request, request
          { expires_in: 10 }
        }
      })

      response = app.get "/s3/multipart/foo/batch", query: { key: "bar", partNumbers: "1,2" }

      assert_match "X-Amz-Expires=10", response.body_json["presignedUrls"]["1"]
      assert_match "X-Amz-Expires=10", response.body_json["presignedUrls"]["2"]
    end
  end


  describe "GET /s3/multipart/:uploadId/:partNumber" do
    it "returns presigned url for part upload" do
      response = app.get "/s3/multipart/foo/1", query: { key: "bar" }

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_match URI.regexp, response.body_json["url"]
    end

    it "returns error response when 'key' parameter is missing" do
      response = app.get "/s3/multipart/foo/1"

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", response.body_json["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: { expires_in: 10 }
      })

      response = app.get "/s3/multipart/foo/1", query: { key: "bar" }

      assert_match "X-Amz-Expires=10", response.body_json["url"]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: -> (request) {
          assert_kind_of Rack::Request, request
          { expires_in: 10 }
        }
      })

      response = app.get "/s3/multipart/foo/1", query: { key: "bar" }

      assert_match "X-Amz-Expires=10", response.body_json["url"]
    end
  end

  describe "POST /s3/multipart/:uploadId/complete" do
    it "completes the multipart upload" do
      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" },
        json: { parts: [{ PartNumber: 1, ETag: "etag1" }] }

      assert_equal :complete_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                      @s3.api_requests[0][:params][:upload_id]
      assert_equal "bar",                      @s3.api_requests[0][:params][:key]
      assert_equal 1,                          @s3.api_requests[0][:params][:multipart_upload][:parts][0][:part_number]
      assert_equal "etag1",                    @s3.api_requests[0][:params][:multipart_upload][:parts][0][:etag]
    end

    it "returns presigned URL to the object" do
      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" }, json: { parts: [] }

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_match URI.regexp, response.body_json["location"]
    end

    it "applies options for object URL" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        object_url: { response_content_disposition: "attachment" }
      })

      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" }, json: { parts: [] }

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_includes response.body_json["location"], "response-content-disposition"
    end

    it "handles :public option" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, public: true)

      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" }, json: { parts: [] }

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      uri = URI.parse(response.body_json["location"])

      assert_nil uri.query
    end

    it "returns error response when 'key' parameter is missing" do
      response = app.post "/s3/multipart/foo/complete", json: { parts: [] }

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", response.body_json["error"]
    end

    it "returns error response when 'parts' parameter is missing" do
      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" }

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Missing \"parts\" parameter", response.body_json["error"]
    end

    it "returns error response when a part is missing 'PartNumber' field" do
      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" },
        json: { parts: [{ ETag: 1 }] }

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "At least one part is missing \"PartNumber\" or \"ETag\" field", response.body_json["error"]
    end

    it "returns error response when a part is missing 'ETag' field" do
      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" },
        json: { parts: [{ PartNumber: 1 }] }

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "At least one part is missing \"PartNumber\" or \"ETag\" field", response.body_json["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        complete_multipart_upload: { request_payer: "bob" }
      })

      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" }, json: { parts: [] }

      assert_equal :complete_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                      @s3.api_requests[0][:params][:request_payer]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        complete_multipart_upload: -> (request) {
          assert_kind_of Rack::Request, request
          { request_payer: "bob" }
        }
      })

      response = app.post "/s3/multipart/foo/complete", query: { key: "bar" }, json: { parts: [] }

      assert_equal :complete_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                      @s3.api_requests[0][:params][:request_payer]
    end
  end

  describe "DELETE /s3/multipart/:uploadId" do
    it "aborts the multipart uplaod" do
      response = app.delete "/s3/multipart/foo", query: { key: "bar" }

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                   @s3.api_requests[0][:params][:upload_id]
      assert_equal "bar",                   @s3.api_requests[0][:params][:key]
    end

    it "returns empty result" do
      response = app.delete "/s3/multipart/foo", query: { key: "bar" }

      assert_equal 200,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal Hash.new, response.body_json
    end

    it "returns error response when 'key' parameter is missing" do
      response = app.delete "/s3/multipart/foo"

      assert_equal 400,                response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", response.body_json["error"]
    end

    it "returns error response when 'key' parameter is for an upload that doesn't exist" do
      @s3.stub_responses(:abort_multipart_upload, 'NoSuchUpload')

      response = app.delete "/s3/multipart/null", query: { key: "null" }

      assert_equal 404, response.status
      assert_equal "application/json", response.headers["Content-Type"]

      assert_equal "Upload doesn't exist for \"key\" parameter", response.body_json["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        abort_multipart_upload: { request_payer: "bob" }
      })

      response = app.delete "/s3/multipart/foo", query: { key: "bar" }

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                   @s3.api_requests[0][:params][:request_payer]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        abort_multipart_upload: -> (request) {
          assert_kind_of Rack::Request, request
          { request_payer: "bob" }
        }
      })

      response = app.delete "/s3/multipart/foo", query: { key: "bar" }

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                   @s3.api_requests[0][:params][:request_payer]
    end
  end

  it "defines #inspect and #to_s" do
    assert_equal "#<Uppy::S3Multipart::App>", @endpoint.inspect
    assert_equal "#<Uppy::S3Multipart::App>", @endpoint.to_s
  end
end
