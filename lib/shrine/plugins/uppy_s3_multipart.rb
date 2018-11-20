require "uppy/s3_multipart"

class Shrine
  module Plugins
    module UppyS3Multipart
      def self.configure(uploader, options = {})
        uploader.opts[:uppy_s3_multipart_options] = (uploader.opts[:uppy_s3_multipart_options] || {}).merge(options[:options] || {})
      end

      module ClassMethods
        def uppy_s3_multipart(storage_key, **options)
          s3 = find_storage(storage_key)

          unless defined?(Shrine::Storage::S3) && s3.is_a?(Shrine::Storage::S3)
            fail Error, "expected storage to be a Shrine::Storage::S3, but was #{s3.inspect}"
          end

          ::Uppy::S3Multipart::App.new(
            bucket:  s3.bucket,
            prefix:  s3.prefix,
            options: opts[:uppy_s3_multipart_options],
            **options
          )
        end
      end
    end

    register_plugin(:uppy_s3_multipart, UppyS3Multipart)
  end
end
