require "test_helper"
require "aws-sdk-s3"
require "uri"

describe Uppy::S3Multipart::Client do
  before do
    resource = Aws::S3::Resource.new(stub_responses: true)
    bucket   = resource.bucket("my-bucket")

    @client = Uppy::S3Multipart::Client.new(bucket: bucket)
    @s3     = bucket.client
  end

  describe "#create_multipart_upload" do
    it "creates a multipart upload" do
      @client.create_multipart_upload(key: "foo")

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                    @s3.api_requests[0][:params][:key]
      assert_equal "my-bucket",              @s3.api_requests[0][:params][:bucket]
    end

    it "returns multipart upload id and key" do
      @s3.stub_responses(:create_multipart_upload, { upload_id: "bar" })

      result = @client.create_multipart_upload(key: "foo")

      assert_equal "bar", result[:upload_id]
      assert_equal "foo", result[:key]
    end

    it "forwards additional option to the aws-sdk call" do
      @client.create_multipart_upload(key: "foo", content_type: "text/plain")

      assert_equal :create_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "text/plain",             @s3.api_requests[0][:params][:content_type]
    end
  end

  describe "#list_parts" do
    it "fetches the list of parts" do
      @client.list_parts(upload_id: "bar", key: "foo")

      assert_equal :list_parts, @s3.api_requests[0][:operation_name]
      assert_equal "foo",       @s3.api_requests[0][:params][:key]
      assert_equal "bar",       @s3.api_requests[0][:params][:upload_id]
      assert_equal "my-bucket", @s3.api_requests[0][:params][:bucket]
    end

    it "returns part numbers, sizes, and etags" do
      @s3.stub_responses(:list_parts, parts: [ { part_number: 1, size: 123, etag: "etag1" } ])

      result = @client.list_parts(upload_id: "bar", key: "foo")

      assert_equal 1,       result[0][:part_number]
      assert_equal 123,     result[0][:size]
      assert_equal "etag1", result[0][:etag]
    end

    it "forwards additional options to the aws-sdk call" do
      @client.list_parts(upload_id: "bar", key: "foo", max_parts: 5)

      assert_equal :list_parts, @s3.api_requests[0][:operation_name]
      assert_equal 5,           @s3.api_requests[0][:params][:max_parts]
    end
  end

  describe "#prepare_upload_part" do
    it "returns a presigned url for uploading a multipart part" do
      result = @client.prepare_upload_part(upload_id: "bar", key: "foo", part_number: 1)

      uri = URI.parse(result.fetch(:url))

      assert_match %r{^my-bucket\.}, uri.host
      assert_match %r{^/foo$},       uri.path
      assert_match %r{uploadId=bar}, uri.query
      assert_match %r{partNumber=1}, uri.query
    end

    it "forwards additional options to the aws-sdk call" do
      result = @client.prepare_upload_part(upload_id: "bar", key: "foo", part_number: 1, content_md5: "foobar")

      uri = URI.parse(result.fetch(:url))

      assert_match %r{X-Amz-SignedHeaders=content-md5}, uri.query
    end
  end

  describe "#complete_multipart_upload" do
    it "completes the multipart upload" do
      @client.complete_multipart_upload(upload_id: "bar", key: "foo", parts: [
        { part_number: 1, etag: "etag1" }
      ])

      assert_equal :complete_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                      @s3.api_requests[0][:params][:key]
      assert_equal "bar",                      @s3.api_requests[0][:params][:upload_id]
      assert_equal "my-bucket",                @s3.api_requests[0][:params][:bucket]
      assert_equal 1,                          @s3.api_requests[0][:params][:multipart_upload][:parts][0][:part_number]
      assert_equal "etag1",                    @s3.api_requests[0][:params][:multipart_upload][:parts][0][:etag]
    end

    it "returns presigned URL to the S3 object" do
      result = @client.complete_multipart_upload(upload_id: "bar", key: "foo", parts: [])

      uri = URI.parse(result.fetch(:location))

      assert_match %r{^my-bucket\.},  uri.host
      assert_match %r{^/foo$},        uri.path
      assert_match %r{X-Amz-Expires}, uri.query
    end

    it "forwards additional options to the aws-sdk call" do
      result = @client.complete_multipart_upload(upload_id: "bar", key: "foo", parts: [], request_payer: "bob")

      assert_equal :complete_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                      @s3.api_requests[0][:params][:request_payer]
    end
  end

  describe "#abort_multipart_upload" do
    it "aborts the multipart upload" do
      @client.abort_multipart_upload(upload_id: "bar", key: "foo")

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                   @s3.api_requests[0][:params][:key]
      assert_equal "bar",                   @s3.api_requests[0][:params][:upload_id]
      assert_equal "my-bucket",             @s3.api_requests[0][:params][:bucket]
    end

    it "retries the abort if it failed" do
      @s3.stub_responses(:list_parts, [
        { parts: [{ part_number: 1, etag: "etag" }] }, # first call
        { parts: [] },                                 # second call
      ])

      @client.abort_multipart_upload(upload_id: "bar", key: "foo")

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "foo",                   @s3.api_requests[0][:params][:key]
      assert_equal "bar",                   @s3.api_requests[0][:params][:upload_id]
      assert_equal "my-bucket",             @s3.api_requests[0][:params][:bucket]

      assert_equal :list_parts,             @s3.api_requests[1][:operation_name]
      assert_equal "foo",                   @s3.api_requests[1][:params][:key]
      assert_equal "bar",                   @s3.api_requests[1][:params][:upload_id]
      assert_equal "my-bucket",             @s3.api_requests[1][:params][:bucket]

      assert_equal :abort_multipart_upload, @s3.api_requests[2][:operation_name]
      assert_equal "foo",                   @s3.api_requests[2][:params][:key]
      assert_equal "bar",                   @s3.api_requests[2][:params][:upload_id]
      assert_equal "my-bucket",             @s3.api_requests[2][:params][:bucket]

      assert_equal :list_parts,             @s3.api_requests[3][:operation_name]
      assert_equal "foo",                   @s3.api_requests[3][:params][:key]
      assert_equal "bar",                   @s3.api_requests[3][:params][:upload_id]
      assert_equal "my-bucket",             @s3.api_requests[3][:params][:bucket]
    end

    it "returns empty result" do
      result = @client.abort_multipart_upload(upload_id: "bar", key: "foo")

      assert_equal Hash.new, result
    end

    it "forwards additional options to the aws-sdk call" do
      @client.abort_multipart_upload(upload_id: "bar", key: "foo", request_payer: "bob")

      assert_equal :abort_multipart_upload, @s3.api_requests[0][:operation_name]
      assert_equal "bob",                   @s3.api_requests[0][:params][:request_payer]
    end
  end
end
