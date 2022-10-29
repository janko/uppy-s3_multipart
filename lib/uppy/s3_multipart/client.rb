require "aws-sdk-s3"

module Uppy
  module S3Multipart
    class Client
      attr_reader :bucket

      def initialize(bucket:)
        @bucket = bucket
      end

      def create_multipart_upload(key:, **options)
        multipart_upload = object(key).initiate_multipart_upload(**options)

        { upload_id: multipart_upload.id, key: multipart_upload.object_key }
      end

      def list_parts(upload_id:, key:, **options)
        multipart_upload = multipart_upload(upload_id, key)
        multipart_parts  = multipart_upload.parts(**options).to_a

        multipart_parts.map do |part|
          { part_number: part.part_number, size: part.size, etag: part.etag }
        end
      end

      def prepare_upload_part(upload_id:, key:, part_number:, **options)
        presigned_url = presigner.presigned_url :upload_part,
          bucket: bucket.name,
          key: object(key).key,
          upload_id: upload_id,
          part_number: part_number,
          body: "",
          **options

        { url: presigned_url }
      end

      def complete_multipart_upload(upload_id:, key:, parts:, **options)
        multipart_upload = multipart_upload(upload_id, key)
        multipart_upload.complete(
          multipart_upload: { parts: parts },
          **options
        )

        { location: object_url(key: key) }
      end

      def object_url(key:, public: nil, **options)
        if public
          object(key).public_url(**options)
        else
          object(key).presigned_url(:get, **options)
        end
      end

      def abort_multipart_upload(upload_id:, key:, **options)
        multipart_upload = multipart_upload(upload_id, key)
        multipart_upload.abort(**options)

        {}
      end

      private

      def multipart_upload(upload_id, key)
        object(key).multipart_upload(upload_id)
      end

      def object(key)
        bucket.object(key)
      end

      def presigner
        Aws::S3::Presigner.new(client: client)
      end

      def client
        bucket.client
      end
    end
  end
end
