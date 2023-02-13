require "test_helper"
require "aws-sdk-s3"
require "rack"
require "rack/test"

describe Uppy::S3Multipart::App do
  include Rack::Test::Methods

  def app
    app = Rack::Builder.new
    app.use Rack::Lint
    app.run Rack::URLMap.new("/s3/multipart" => -> (env) { @endpoint.call(env) })
    app
  end

  before do
    resource = Aws::S3::Resource.new(stub_responses: true)
    @bucket  = resource.bucket("my-bucket")

    @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket)
    @s3       = @bucket.client

    header "Content-Type", "application/json"
  end

  describe "POST /s3/multipart" do
    it "creates a multipart upload" do
      post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_match /^\w{32}$/,               @s3.api_requests[0][:params][:key]
    end

    it "returns multipart upload id and key" do
      @s3.stub_responses(:create_multipart_upload, { upload_id: "foo", key: "bar" })

      post "/s3/multipart"

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "foo",      JSON.parse(last_response.body)["uploadId"]
      assert_match /^\w{32}$/, JSON.parse(last_response.body)["key"]
    end

    it "handles 'type' JSON body parameter" do
      post "/s3/multipart", JSON.generate({ type: "text/plain" })

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "text/plain",             @s3.api_requests[0][:params][:content_type]
    end

    it "handles 'filename' JSON body parameter" do
      post "/s3/multipart", JSON.generate({ filename: "nature.jpg" })

      expected_content_disposition = %(inline; filename="nature.jpg"; filename*=UTF-8''nature.jpg)

      assert_equal :create_multipart_upload,     @s3.api_requests[0][:operation_name]
      assert_equal expected_content_disposition, @s3.api_requests[0][:params][:content_disposition]

      assert_match /^\w{32}\.jpg$/, JSON.parse(last_response.body)["key"]
    end

    it "handles :prefix option" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, prefix: "prefix")

      post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_match /^prefix\/\w{32}/,        @s3.api_requests[0][:params][:key]

      assert_match /^prefix\/\w{32}$/, JSON.parse(last_response.body)["key"]
    end

    it "handles :public option" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, public: true)

      post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "public-read",            @s3.api_requests[0][:params][:acl]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        create_multipart_upload: { acl: "public-read" }
      })

      post "/s3/multipart"

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

      post "/s3/multipart"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "public-read",            @s3.api_requests[0][:params][:acl]
    end

    it "works with a trailing slash (for Rails)" do
      post "/s3/multipart/"

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_match /^\w{32}$/,               @s3.api_requests[0][:params][:key]
    end
  end

  describe "OPTIONS /s3/multipart/:uploadId/:partNumber" do
    it "returns an empty response" do
      options "/s3/multipart/foo/1"

      assert_equal 204,      last_response.status
      assert_equal Hash.new, last_response.headers
      assert_equal "",       last_response.body
    end
  end

  describe "OPTIONS /s3/multipart" do
    it "returns an empty response" do
      options "/s3/multipart"

      assert_equal 204,      last_response.status
      assert_equal Hash.new, last_response.headers
      assert_equal "",       last_response.body
    end
  end

  describe "GET /s3/multipart/:uploadId" do
    it "fetches multipart parts" do
      get "/s3/multipart/foo", { key: "bar" }

      assert_equal :list_parts, @s3.api_requests[0][:operation_name]
      assert_equal "foo",       @s3.api_requests[0][:params][:upload_id]
      assert_equal "bar",       @s3.api_requests[0][:params][:key]
    end

    it "returns multipart parts" do
      @s3.stub_responses(:list_parts, { parts: [ { part_number: 1, size: 123, etag: "etag1" } ] })

      get "/s3/multipart/foo", { key: "bar" }

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal 1,       JSON.parse(last_response.body)[0]["PartNumber"]
      assert_equal 123,     JSON.parse(last_response.body)[0]["Size"]
      assert_equal "etag1", JSON.parse(last_response.body)[0]["ETag"]
    end

    it "returns error response when 'key' parameter is missing" do
      get "/s3/multipart/foo"

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        list_parts: { max_parts: 5 }
      })

      get "/s3/multipart/foo", { key: "bar" }

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

      get "/s3/multipart/foo", { key: "bar" }

      assert_equal :list_parts,   @s3.api_requests[0][:operation_name]
      assert_equal 5,             @s3.api_requests[0][:params][:max_parts]
    end
  end

  describe "GET /s3/multipart/:uploadId/batch" do
    it "returns presigned urls for batch part upload" do
      get "/s3/multipart/foo/batch", { key: "bar", partNumbers: "1,2" }

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_match URI.regexp, JSON.parse(last_response.body)["presignedUrls"]["1"]
      assert_match URI.regexp, JSON.parse(last_response.body)["presignedUrls"]["2"]
    end

    it "returns error response when 'key' parameter is missing" do
      get "/s3/multipart/foo/batch", { partNumbers: "1,2" }

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "returns error response when 'partNumbers' parameter is missing" do
      get "/s3/multipart/foo/batch", { key: "bar" }

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Missing \"partNumbers\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: { expires_in: 10 }
      })

      get "/s3/multipart/foo/batch", { key: "bar", partNumbers: "1,2" }

      assert_match "X-Amz-Expires=10", JSON.parse(last_response.body)["presignedUrls"]["1"]
      assert_match "X-Amz-Expires=10", JSON.parse(last_response.body)["presignedUrls"]["2"]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: -> (request) {
          assert_kind_of Rack::Request, request
          { expires_in: 10 }
        }
      })

      get "/s3/multipart/foo/batch", { key: "bar", partNumbers: "1,2" }

      assert_match "X-Amz-Expires=10", JSON.parse(last_response.body)["presignedUrls"]["1"]
      assert_match "X-Amz-Expires=10", JSON.parse(last_response.body)["presignedUrls"]["2"]
    end
  end


  describe "GET /s3/multipart/:uploadId/:partNumber" do
    it "returns presigned url for part upload" do
      get "/s3/multipart/foo/1", { key: "bar" }

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_match URI.regexp, JSON.parse(last_response.body)["url"]
    end

    it "returns error response when 'key' parameter is missing" do
      get "/s3/multipart/foo/1"

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: { expires_in: 10 }
      })

      get "/s3/multipart/foo/1", { key: "bar" }

      assert_match "X-Amz-Expires=10", JSON.parse(last_response.body)["url"]
    end

    it "handles :options as a block" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        prepare_upload_part: -> (request) {
          assert_kind_of Rack::Request, request
          { expires_in: 10 }
        }
      })

      get "/s3/multipart/foo/1", { key: "bar" }

      assert_match "X-Amz-Expires=10", JSON.parse(last_response.body)["url"]
    end
  end

  describe "POST /s3/multipart/:uploadId/complete" do
    it "completes the multipart upload" do
      post "/s3/multipart/foo/complete",
        JSON.generate({ parts: [{ PartNumber: 1, ETag: "etag1" }] }),
        query_params: { key: "bar" }

      assert_equal :complete_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                      @s3.api_requests[0][:params][:upload_id]
      assert_equal "bar",                      @s3.api_requests[0][:params][:key]
      assert_equal 1,                          @s3.api_requests[0][:params][:multipart_upload][:parts][0][:part_number]
      assert_equal "etag1",                    @s3.api_requests[0][:params][:multipart_upload][:parts][0][:etag]
    end

    it "returns presigned URL to the object" do
      post "/s3/multipart/foo/complete", JSON.generate({ parts: [] }), query_params: { key: "bar" }

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_match URI.regexp, JSON.parse(last_response.body)["location"]
    end

    it "applies options for object URL" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        object_url: { response_content_disposition: "attachment" }
      })

      post "/s3/multipart/foo/complete", JSON.generate({ parts: [] }), query_params: { key: "bar" }

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_includes JSON.parse(last_response.body)["location"], "response-content-disposition"
    end

    it "handles :public option" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, public: true)

      post "/s3/multipart/foo/complete", JSON.generate({ parts: [] }), query_params: { key: "bar" }

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      uri = URI.parse(JSON.parse(last_response.body)["location"])

      assert_nil uri.query
    end

    it "returns error response when 'key' parameter is missing" do
      post "/s3/multipart/foo/complete", JSON.generate({ parts: [] })

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "returns error response when 'parts' parameter is missing" do
      post "/s3/multipart/foo/complete", nil, query_params: { key: "bar" }

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Missing \"parts\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "returns error response when a part is missing 'PartNumber' field" do
      post "/s3/multipart/foo/complete", JSON.generate({ parts: [{ ETag: 1 }] }), query_params: { key: "bar" }

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "At least one part is missing \"PartNumber\" or \"ETag\" field", JSON.parse(last_response.body)["error"]
    end

    it "returns error response when a part is missing 'ETag' field" do
      post "/s3/multipart/foo/complete", JSON.generate({ parts: [{ PartNumber: 1 }] }), query_params: { key: "bar" }

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "At least one part is missing \"PartNumber\" or \"ETag\" field", JSON.parse(last_response.body)["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        complete_multipart_upload: { request_payer: "bob" }
      })

      post "/s3/multipart/foo/complete", JSON.generate({ parts: [] }), query_params: { key: "bar" }

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

      post "/s3/multipart/foo/complete", JSON.generate({ parts: [] }), query_params: { key: "bar" }

      assert_equal :complete_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                      @s3.api_requests[0][:params][:request_payer]
    end
  end

  describe "DELETE /s3/multipart/:uploadId" do
    it "aborts the multipart uplaod" do
      delete "/s3/multipart/foo", nil, query_params: { key: "bar" }

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                   @s3.api_requests[0][:params][:upload_id]
      assert_equal "bar",                   @s3.api_requests[0][:params][:key]
    end

    it "returns empty result" do
      delete "/s3/multipart/foo", nil, query_params: { key: "bar" }

      assert_equal 200,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal Hash.new, JSON.parse(last_response.body)
    end

    it "returns error response when 'key' parameter is missing" do
      delete "/s3/multipart/foo"

      assert_equal 400,                last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Missing \"key\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "returns error response when 'key' parameter is for an upload that doesn't exist" do
      @s3.stub_responses(:abort_multipart_upload, 'NoSuchUpload')

      delete "/s3/multipart/null", nil, query_params: { key: "null" }

      assert_equal 404, last_response.status
      assert_equal "application/json", last_response.headers["Content-Type"]

      assert_equal "Upload doesn't exist for \"key\" parameter", JSON.parse(last_response.body)["error"]
    end

    it "handles :options as a hash" do
      @endpoint = Uppy::S3Multipart::App.new(bucket: @bucket, options: {
        abort_multipart_upload: { request_payer: "bob" }
      })

      delete "/s3/multipart/foo", nil, query_params: { key: "bar" }

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

      delete "/s3/multipart/foo", nil, query_params: { key: "bar" }

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                   @s3.api_requests[0][:params][:request_payer]
    end
  end

  it "defines #inspect and #to_s" do
    assert_equal "#<Uppy::S3Multipart::App>", @endpoint.inspect
    assert_equal "#<Uppy::S3Multipart::App>", @endpoint.to_s
  end
end
