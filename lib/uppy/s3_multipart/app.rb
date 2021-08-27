require "uppy/s3_multipart/client"

require "roda"
require "content_disposition"

require "securerandom"

module Uppy
  module S3Multipart
    class App
      def initialize(bucket:, prefix: nil, public: nil, options: {})
        @router = Class.new(Router)
        @router.opts[:client]  = Client.new(bucket: bucket)
        @router.opts[:prefix]  = prefix
        @router.opts[:public]  = public
        @router.opts[:options] = options
      end

      def call(env)
        @router.call(env)
      end

      def inspect
        "#<Uppy::S3Multipart::App>"
      end
      alias to_s inspect

      class Router < Roda
        plugin :all_verbs
        plugin :json
        plugin :json_parser
        plugin :halt
        plugin :path_rewriter

        # allow mounting on "/s3" for backwards compatibility
        rewrite_path "/multipart", ""

        route do |r|
          # POST /s3/multipart
          r.post ["", true] do
            type     = r.params["type"]
            filename = r.params["filename"]

            key = SecureRandom.hex + File.extname(filename.to_s)
            key = [*opts[:prefix], key].join("/")

            options = {}
            options[:content_type]        = type if type
            options[:content_disposition] = ContentDisposition.inline(filename) if filename
            options[:acl]                 = "public-read" if opts[:public]

            result = client_call(:create_multipart_upload, key: key, **options)

            { uploadId: result.fetch(:upload_id), key: result.fetch(:key) }
          end

          # OPTIONS /s3/multipart
          r.options ["", true] do
            r.halt 204
          end

          # OPTIONS /s3/multipart/:uploadId/:partNumber
          r.options String, String do |upload_id, part_number|
            r.halt 204
          end

          # GET /s3/multipart/:uploadId
          r.get String do |upload_id|
            key = param!("key")

            result = client_call(:list_parts, upload_id: upload_id, key: key)

            result.map do |part|
              { PartNumber: part.fetch(:part_number), Size: part.fetch(:size), ETag: part.fetch(:etag) }
            end
          end

          # GET /s3/multipart/:uploadId/:partNumber
          r.get String, String do |upload_id, part_number|
            key = param!("key")

            result = client_call(:prepare_upload_part, upload_id: upload_id, key: key, part_number: part_number)

            { url: result.fetch(:url) }
          end

          # POST /s3/multipart/:uploadId/complete
          r.post String, "complete" do |upload_id|
            key   = param!("key")
            parts = param!("parts")

            parts = parts.map do |part|
              begin
                { part_number: part.fetch("PartNumber"), etag: part.fetch("ETag") }
              rescue KeyError
                error! "At least one part is missing \"PartNumber\" or \"ETag\" field"
              end
            end

            client_call(:complete_multipart_upload, upload_id: upload_id, key: key, parts: parts)

            object_url = client_call(:object_url, key: key, public: opts[:public])

            { location: object_url }
          end

          # DELETE /s3/multipart/:uploadId
          r.delete String do |upload_id|
            key = param!("key")

            begin
              client_call(:abort_multipart_upload, upload_id: upload_id, key: key)
            rescue Aws::S3::Errors::NoSuchUpload
              error!(
                "Upload doesn't exist for \"key\" parameter",
                status: 404
              )
            end

            {}
          end
        end

        def client_call(operation, **options)
          client = opts[:client]

          overrides = opts[:options][operation] || {}
          overrides = overrides.call(request) if overrides.respond_to?(:call)

          options = options.merge(overrides)

          client.send(operation, **options)
        end

        def param!(name)
          value = request.params[name]

          error! "Missing \"#{name}\" parameter" if value.nil?

          value
        end

        def error!(message, status: 400)
          request.halt status, { error: message }
        end
      end
    end
  end
end
