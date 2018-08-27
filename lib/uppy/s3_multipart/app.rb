require "uppy/s3_multipart/client"

require "roda"

require "securerandom"
require "cgi"

module Uppy
  module S3Multipart
    class App
      def initialize(bucket:, prefix: nil, options: {})
        @router = Class.new(Router)
        @router.opts[:client]  = Client.new(bucket: bucket)
        @router.opts[:prefix]  = prefix
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

        route do |r|
          # POST /multipart
          r.post "multipart" do
            content_type = r.params["type"]
            filename     = r.params["filename"]

            extension = File.extname(filename.to_s)
            key       = SecureRandom.hex + extension
            key       = "#{opts[:prefix]}/#{key}" if opts[:prefix]

            # CGI-escape the filename because aws-sdk's signature calculator trips on special characters
            content_disposition = "inline; filename=\"#{CGI.escape(filename)}\"" if filename

            result = client_call(:create_multipart_upload, key: key, content_type: content_type, content_disposition: content_disposition)

            { uploadId: result.fetch(:upload_id), key: result.fetch(:key) }
          end

          # GET /multipart/:uploadId
          r.get "multipart", String do |upload_id|
            key = param!("key")

            result = client_call(:list_parts, upload_id: upload_id, key: key)

            result.map do |part|
              { PartNumber: part.fetch(:part_number), Size: part.fetch(:size), ETag: part.fetch(:etag) }
            end
          end

          # GET /multipart/:uploadId/:partNumber
          r.get "multipart", String, String do |upload_id, part_number|
            key = param!("key")

            result = client_call(:prepare_upload_part, upload_id: upload_id, key: key, part_number: part_number)

            { url: result.fetch(:url) }
          end

          # POST /multipart/:uploadId/complete
          r.post "multipart", String, "complete" do |upload_id|
            key   = param!("key")
            parts = param!("parts")

            parts = parts.map do |part|
              begin
                { part_number: part.fetch("PartNumber"), etag: part.fetch("ETag") }
              rescue KeyError
                r.halt 400, { error: "At least one part is missing \"PartNumber\" or \"ETag\" field" }
              end
            end

            result = client_call(:complete_multipart_upload, upload_id: upload_id, key: key, parts: parts)

            { location: result.fetch(:location) }
          end

          # DELETE /multipart/:uploadId
          r.delete "multipart", String do |upload_id|
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

          request.halt 400, { error: "Missing \"#{name}\" parameter" } if value.nil?

          value
        end
      end
    end
  end
end
