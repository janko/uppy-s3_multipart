require "uppy/s3_multipart/client"

require "roda"

require "securerandom"
require "cgi"

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
          r.post true do
            content_type = r.params["type"]
            filename     = r.params["filename"]

            extension = File.extname(filename.to_s)
            key       = SecureRandom.hex + extension
            key       = "#{opts[:prefix]}/#{key}" if opts[:prefix]

            # CGI-escape the filename because aws-sdk's signature calculator trips on special characters
            content_disposition = "inline; filename=\"#{CGI.escape(filename)}\"" if filename

            options = { content_type: content_type, content_disposition: content_disposition }
            options[:acl] = "public-read" if opts[:public]

            result = client_call(:create_multipart_upload, key: key, **options)

            { uploadId: result.fetch(:upload_id), key: result.fetch(:key) }
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

            client_call(:abort_multipart_upload, upload_id: upload_id, key: key)

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

        def error!(message)
          request.halt 400, { error: message }
        end
      end
    end
  end
end
