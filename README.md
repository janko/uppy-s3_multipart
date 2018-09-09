# Uppy::S3Multipart

Provides a Rack application that implements endpoints for the [AwsS3Multipart]
Uppy plugin. This enables multipart uploads directly to S3, which is
recommended when dealing with large files, as it allows resuming interrupted
uploads.

## Installation

Add the gem to your Gemfile:

```rb
gem "uppy-s3_multipart"
```

## Setup

In order to allow direct multipart uploads to your S3 bucket, we need to update
the bucket's CORS configuration. In the AWS S3 Console go to your bucket, click
on "Permissions" tab and then on "CORS configuration". There paste in the
following:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CORSConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <CORSRule>
    <AllowedOrigin>https://my-app.com</AllowedOrigin>
    <AllowedMethod>GET</AllowedMethod>
    <AllowedMethod>POST</AllowedMethod>
    <AllowedMethod>PUT</AllowedMethod>
    <MaxAgeSeconds>3000</MaxAgeSeconds>
    <AllowedHeader>Authorization</AllowedHeader>
    <AllowedHeader>x-amz-date</AllowedHeader>
    <AllowedHeader>x-amz-content-sha256</AllowedHeader>
    <AllowedHeader>content-type</AllowedHeader>
    <ExposeHeader>ETag</ExposeHeader>
  </CORSRule>
  <CORSRule>
    <AllowedOrigin>*</AllowedOrigin>
    <AllowedMethod>GET</AllowedMethod>
    <MaxAgeSeconds>3000</MaxAgeSeconds>
  </CORSRule>
</CORSConfiguration>
```

Replace `https://my-app.com` with the URL to your app (in development you can
set this to `*`). Once you've clicked `Save`, it may take some time for the
new CORS settings to be applied.

## Usage

This gem provides a Rack application that you can mount inside your main
application. If you're using [Shrine], you can initialize the Rack application
via the `uppy_s3_multipart` Shrine plugin, otherwise you can initialize it
directly.

### Shrine

In the initializer load the `uppy_s3_multipart` plugin:

```rb
require "shrine"
require "shrine/storage/s3"

Shrine.storages = {
  cache: Shrine::Storage::S3.new(...),
  store: Shrine::Storage::S3.new(...),
}

# ...
Shrine.plugin :uppy_s3_multipart # load the plugin
```

The plugin will provide a `Shrine.uppy_s3_multipart` method, which returns an
instance of `Uppy::S3Multipart::App`, which is a Rack app that you can mount
inside your main application:

```rb
# Rails (config/routes.rb)
Rails.application.routes.draw do
  mount Shrine.uppy_s3_multipart(:cache) => "/s3"
end

# Rack (config.ru)
map "/s3" do
  run Shrine.uppy_s3_multipart(:cache)
end
```

This will add the routes that the `AwsS3Multipart` Uppy plugin expects:

```
POST   /s3/multipart
GET    /s3/multipart/:uploadId
GET    /s3/multipart/:uploadId/:partNumber
POST   /s3/multipart/:uploadId/complete
DELETE /s3/multipart/:uploadId
```

Finally, in your Uppy configuration pass your app's URL as the `serverUrl`:

```js
// ...
uppy.use(Uppy.AwsS3Multipart, {
  serverUrl: 'https://your-app.com/',
})
```

**See [Adding Direct S3 Uploads] for an example of a complete Uppy setup with
Shrine. From there you can just swap the `AwsS3` Uppy plugin for the
`AwsS3Multipart` plugin, and `presign_endpoint` Shrine plugin for the
`uppy_s3_multipart` plugin.**

Both the plugin and method accepts `:options` for specifying additional options
to the aws-sdk calls (read further for more details on these options):

```rb
Shrine.plugin :uppy_s3_multipart, options: {
  create_multipart_upload: { acl: "public-read" } # static
}

# OR

Shrine.uppy_s3_multipart(:cache, options: {
  create_multipart_upload: -> (request) { { acl: "public-read" } } # dynamic
})
```

### Standalone

You can also initialize `Uppy::S3Multipart::App` directly:

```rb
require "uppy/s3_multipart"

resource = Aws::S3::Resource.new(
  access_key_id:     "...",
  secret_access_key: "...",
  region:            "...",
)

bucket = resource.bucket("my-bucket")

UPPY_S3_MULTIPART_APP = Uppy::S3Multipart::App.new(bucket: bucket)
```

and mount it in your app in the same way:

```rb
# Rails (config/routes.rb)
Rails.application.routes.draw do
  mount UPPY_S3_MULTIPART_APP => "/s3"
end

# Rack (config.ru)
map "/s3" do
  run UPPY_S3_MULTIPART_APP
end
```

In your Uppy configuration point the `serverUrl` to your application:

```js
// ...
uppy.use(Uppy.AwsS3Multipart, {
  serverUrl: "https://your-app.com/",
})
```

The `Uppy::S3Mutipart::App` initializer accepts `:options` for specifying
additional options to the aws-sdk calls (read further for more details on these
options):

```rb
Uppy::S3Multipart::App.new(bucket: bucket, options: {
  create_multipart_upload: { acl: "public-read" }
})

# OR

Uppy::S3Multipart::App.new(bucket: bucket, options: {
  create_multipart_upload: -> (request) { { acl: "public-read" } }
})
```

### Custom implementation

If you would rather implement the endpoints yourself, you can utilize
`Uppy::S3Multipart::Client` to make S3 requests.

```rb
require "uppy/s3_multipart/client"

client = Uppy::S3Multipart::Client.new(bucket: bucket)
```

#### `create_multipart_upload`

Initiates a new multipart upload.

```rb
client.create_multipart_upload(key: "foo", **options)
#=> { upload_id: "MultipartUploadId", key: "foo" }
```

Accepts:

* `:key` -- object key
* additional options for [`Aws::S3::Client#create_multipart_upload`]

Returns:

* `:upload_id` -- id of the created multipart upload
* `:key` -- object key

#### `#list_parts`

Retrieves currently uploaded parts of a multipart upload.

```rb
client.list_parts(upload_id: "MultipartUploadId", key: "foo", **options)
#=> [ { part_number: 1, size: 5402383, etag: "etag1" },
#     { part_number: 2, size: 5982742, etag: "etag2" },
#     ... ]
```

Accepts:

* `:upload_id` -- multipart upload id
* `:key` -- object key
* additional options for [`Aws::S3::Client#list_parts`]

Returns:

* array of parts

  - `:part_number` -- position of the part
  - `:size` -- filesize of the part
  - `:etag` -- etag of the part

#### `#prepare_upload_part`

Returns the endpoint that should be used for uploading a new multipart part.

```rb
client.prepare_upload_part(upload_id: "MultipartUploadId", key: "foo", part_number: 1, **options)
#=> { url: "https://my-bucket.s3.amazonaws.com/foo?partNumber=1&uploadId=MultipartUploadId&..." }
```

Accepts:

* `:upload_id` -- multipart upload id
* `:key` -- object key
* `:part_number` -- number of the next part
* additional options for [`Aws::S3::Client#upload_part`] and [`Aws::S3::Presigner#presigned_url`]

Returns:

* `:url` -- endpoint that should be used for uploading a new multipart part via a `PUT` request

#### `#complete_multipart_upload`

Finalizes the multipart upload and returns URL to the object.

```rb
client.complete_multipart_upload(upload_id: upload_id, key: key, parts: [{ part_number: 1, etag: "etag1" }], **options)
#=> { location: "https://my-bucket.s3.amazonaws.com/foo?..." }
```

Accepts:

* `:upload_id` -- multipart upload id
* `:key` -- object key
* `:parts` -- list of all uploaded parts, consisting of `:part_number` and `:etag`
* additional options for [`Aws::S3::Client#complete_multipart_upload`]

Returns:

* `:location` -- URL to the uploaded object

#### `#abort_multipart_upload`

Aborts the multipart upload, removing all parts uploaded so far.

```rb
client.abort_multipart_upload(upload_id: upload_id, key: key, **options)
#=> {}
```

Accepts:

* `:upload_id` -- multipart upload id
* `:key` -- object key
* additional options for [`Aws::S3::Client#abort_multipart_upload`]

## Contributing

You can run the test suite with

```
$ bundle exec rake test
```

This project is intended to be a safe, welcoming space for collaboration, and
contributors are expected to adhere to the [Contributor
Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT
License](https://opensource.org/licenses/MIT).

[AwsS3Multipart]: https://uppy.io/docs/aws-s3-multipart/
[Shrine]: https://shrinerb.com
[Adding Direct S3 Uploads]: https://github.com/shrinerb/shrine/wiki/Adding-Direct-S3-Uploads
[`Aws::S3::Client#create_multipart_upload`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#create_multipart_upload-instance_method
[`Aws::S3::Client#list_parts`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#list_parts-instance_method
[`Aws::S3::Client#upload_part`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#upload_part-instance_method
[`Aws::S3::Presigner#presigned_url`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Presigner.html#presigned_url-instance_method
[`Aws::S3::Client#complete_multipart_upload`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#complete_multipart_upload-instance_method
[`Aws::S3::Client#abort_multipart_upload`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#abort_multipart_upload-instance_method
