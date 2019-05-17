# Uppy::S3Multipart

Provides a Rack application that implements endpoints for the [aws-s3-multipart]
Uppy plugin. This enables multipart uploads directly to S3, which is
recommended when dealing with large files, as it allows resuming interrupted
uploads.

## Installation

Add the gem to your Gemfile:

```rb
gem "uppy-s3_multipart", "~> 0.3"
```

## Setup

In order to allow direct multipart uploads to your S3 bucket, you need to update
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
set this to `*`). Once you've hit "Save", it may take some time for the new
CORS settings to be applied.

## Usage

This gem provides a Rack application that you can mount inside your main
application. If you're using [Shrine], you can initialize the Rack application
via the [Shrine plugin](#shrine).

### App

At its core, you initialize an `Uppy::S3Multipart::App` with an
`Aws::S3::Bucket` object:

```rb
require "uppy/s3_multipart"

bucket = Aws::S3::Bucket.new(
  name:              "my-bucket",
  access_key_id:     "...",
  secret_access_key: "...",
  region:            "...",
)

UPPY_S3_MULTIPART_APP = Uppy::S3Multipart::App.new(bucket: bucket)
```

The instance of `Uppy::S3Multipart::App` is a Rack application that can be
mounted in your router (`config/routes.rb` in Rails). It should be
mounted at `/s3/multipart`:

```rb
# config/routes.rb (Rails)
Rails.application.routes.draw do
  # ...
  mount UPPY_S3_MULTIPART_APP => "/s3/multipart"
end
```

This will add the routes that the `aws-s3-multipart` Uppy plugin expects:

```
POST   /s3/multipart
GET    /s3/multipart/:uploadId
GET    /s3/multipart/:uploadId/:partNumber
POST   /s3/multipart/:uploadId/complete
DELETE /s3/multipart/:uploadId
```

Since your app will now play the role of Uppy Companion, in your Uppy
configuration you can point `companionUrl` to your app's URL:

```js
// ...
uppy.use(Uppy.AwsS3Multipart, {
  companionUrl: '/',
})
```

### Shrine

If you're using Shrine, you can use the `uppy_s3_multipart` Shrine plugin that
ships with this gem to simplify the setup.

In your Shrine initializer load the `uppy_s3_multipart` plugin:

```rb
require "shrine"
require "shrine/storage/s3"

Shrine.storages = {
  cache: Shrine::Storage::S3.new(prefix: "cache", ...),
  store: Shrine::Storage::S3.new(...),
}

# ...
Shrine.plugin :uppy_s3_multipart # load the plugin
```

The plugin will provide a `Shrine.uppy_s3_multipart` method that creates the
`Uppy::S3Multipart::App` instance, which you can then mount inside your router:

```rb
# config/routes.rb (Rails)
Rails.application.routes.draw do
  # ...
  mount Shrine.uppy_s3_multipart(:cache) => "/s3/multipart"
end
```

Now in your Uppy configuration point `companionUrl` to your app's URL:

```js
// ...
uppy.use(Uppy.AwsS3Multipart, {
  companionUrl: '/',
})
```

In the `upload-success` Uppy callback, you can construct the Shrine uploaded
file data (this example assumes your temporary Shrine S3 storage has `prefix:
"cache"` set):

```js
uppy.on('upload-success', function (file, response) {
  var uploadedFileData = JSON.stringify({
    id: response.uploadURL.match(/\/cache\/([^\?]+)/)[1], // extract key without prefix
    storage: 'cache',
    metadata: {
      size:      file.size,
      filename:  file.name,
      mime_type: file.type,
    }
  })
  // ...
})
```

See [Adding Direct S3 Uploads] for an example of a complete Uppy setup with
Shrine. From there you can swap the `presign_endpoint` + `aws-s3` code with the
`uppy_s3_multipart` + `aws-s3-multipart` setup.

Note that **Shrine won't extract metadata from directly upload files on
assignment** by default. Instead, it will just copy metadata that was extracted
on the client side. See [this section][metadata direct uploads] for the
rationale and instructions on how to opt in.

### Configuration

This section describe various configuration options that you can pass to
`Uppy::S3Multipart::App`.

#### `:bucket`

The `:bucket` option is mandatory and accepts an instance of `Aws::S3::Bucket`:

```rb
require "uppy/s3_multipart"

bucket = Aws::S3::Bucket.new(
  name:              "<BUCKET>",
  access_key_id:     "<ACCESS_KEY_ID>",
  secret_access_key: "<SECRET_ACCESS_KEY>",
  region:            "<REGION>",
)

Uppy::S3Multipart::App.new(bucket: bucket)
```

If you want to use [Minio], you can easily configure the `Aws::S3::Bucket` to
use your Minio server:

```rb
bucket = Aws::S3::Bucket.new(
  name:              "<MINIO_BUCKET>",
  access_key_id:     "<MINIO_ACCESS_KEY>", # "AccessKey" value
  secret_access_key: "<MINIO_SECRET_KEY>", # "SecretKey" value
  endpoint:          "<MINIO_ENDPOINT>",   # "Endpoint"  value
  region:            "us-east-1",
)

Uppy::S3Multipart::App.new(bucket: bucket)
```

Except for `:name`, all options passed to [`Aws::S3::Bucket#initialize`] are
forwarded to [`Aws::S3::Client#initialize`], see its documentation for
additional options.

In the Shrine plugin this configuration is inferred from the S3 storage.

#### `:prefix`

The `:prefix` option allows you to specify a directory which you want the files
to be uploaded to.

```rb
Uppy::S3Multipart::App.new(bucket: bucket, prefix: "cache")
```

In the Shrine plugin this option is inferred from the S3 storage.

#### `:options`

The `:options` option allows you to pass additional parameters to [Client]
operations. With the Shrine plugin they can be passed when initializing the
plugin:

```rb
Shrine.plugin :uppy_s3_multipart, options: { ... }
```

or when creating the app:

```rb
Shrine.uppy_s3_multipart(:cache, options: { ... })
```

In the end they are just forwarded to `Uppy::S3Multipart::App#initialize`:

```rb
Uppy::S3Multipart::App.new(bucket: bucket, options: { ... })
```

In the `:options` hash keys are [Client] operation names, and values are the
parameters. The parameters can be provided statically:

```rb
options: {
  create_multipart_upload: { cache_control: "max-age=#{365*24*60*60}" },
  prepare_upload_part:     { expires_in: 10 },
}
```

or generated dynamically for each request, in which case a [`Rack::Request`]
object is also passed to the block:

```rb
options: {
  create_multipart_upload: -> (request) {
    { key: SecureRandom.uuid }
  }
}
```

The initial request to `POST /s3/multipart` (which calls the
`#create_multipart_upload` operation) will contain `type` and `filename` query
parameters, so for example you could use that to make requesting the URL later
force a download with the original filename (using the [content_disposition]
gem):

```rb
options: {
  create_multipart_upload: -> (request) {
    filename = request.params["filename"]

    { content_disposition: ContentDisposition.attachment(filename) }
  }
}
```

See the [Client] section for list of operations and parameters they accept.

#### `:public`

The `:public` option sets the ACL of uploaded objects to `public-read`, and
makes sure the object URL returned at the end is a public non-expiring URL
without query parameters.

```rb
Uppy::S3Multipart::App.new(bucket: bucket, public: true)
```

It's really just a shorthand for:

```rb
Uppy::S3Multipart::App.new(bucket: bucket, options: {
  create_multipart_upload: { acl: "public-read" },
  object_url: { public: true },
})
```

In the Shrine plugin this option is inferred from the S3 storage (available
from Shrine 2.13):

```rb
Shrine.storages = {
  cache: Shrine::Storage::S3.new(prefix: "cache", public: true, **options),
  store: Shrine::Storage::S3.new(**options),
}
```

### Client

If you would rather implement the endpoints yourself, you can utilize the
`Uppy::S3Multipart::Client` to make S3 requests.

```rb
require "uppy/s3_multipart/client"

client = Uppy::S3Multipart::Client.new(bucket: bucket)
```

#### `#create_multipart_upload`

Initiates a new multipart upload.

```rb
client.create_multipart_upload(key: "foo", **options)
# => { upload_id: "MultipartUploadId", key: "foo" }
```

Accepts:

* `:key` – object key
* additional options for [`Aws::S3::Client#create_multipart_upload`]

Returns:

* `:upload_id` – id of the created multipart upload
* `:key` – object key

#### `#list_parts`

Retrieves currently uploaded parts of a multipart upload.

```rb
client.list_parts(upload_id: "MultipartUploadId", key: "foo", **options)
# => [ { part_number: 1, size: 5402383, etag: "etag1" },
#      { part_number: 2, size: 5982742, etag: "etag2" },
#      ... ]
```

Accepts:

* `:upload_id` – multipart upload id
* `:key` – object key
* additional options for [`Aws::S3::Client#list_parts`]

Returns:

* array of parts

  - `:part_number` – position of the part
  - `:size` – filesize of the part
  - `:etag` – etag of the part

#### `#prepare_upload_part`

Returns the endpoint that should be used for uploading a new multipart part.

```rb
client.prepare_upload_part(upload_id: "MultipartUploadId", key: "foo", part_number: 1, **options)
# => { url: "https://my-bucket.s3.amazonaws.com/foo?partNumber=1&uploadId=MultipartUploadId&..." }
```

Accepts:

* `:upload_id` – multipart upload id
* `:key` – object key
* `:part_number` – number of the next part
* additional options for [`Aws::S3::Client#upload_part`] and [`Aws::S3::Presigner#presigned_url`]

Returns:

* `:url` – endpoint that should be used for uploading a new multipart part via a `PUT` request

#### `#complete_multipart_upload`

Finalizes the multipart upload and returns URL to the object.

```rb
client.complete_multipart_upload(upload_id: upload_id, key: key, parts: [{ part_number: 1, etag: "etag1" }], **options)
# => { location: "https://my-bucket.s3.amazonaws.com/foo?..." }
```

Accepts:

* `:upload_id` – multipart upload id
* `:key` – object key
* `:parts` – list of all uploaded parts, consisting of `:part_number` and `:etag`
* additional options for [`Aws::S3::Client#complete_multipart_upload`]

Returns:

* `:location` – URL to the uploaded object

#### `#object_url`

Generates URL to the object.

```rb
client.object_url(key: key, **options)
# => "https://my-bucket.s3.amazonaws.com/foo?..."
```

This is called after `#complete_multipart_upload` in the app and returned in
the response.

Accepts:

* `:key` – object key
* `:public` – for generating a public URL (default is presigned expiring URL)
* additional options for [`Aws::S3::Object#presigned_url`] and [`Aws::S3::Client#get_object`]

Returns:

* URL to the object

#### `#abort_multipart_upload`

Aborts the multipart upload, removing all parts uploaded so far.

```rb
client.abort_multipart_upload(upload_id: upload_id, key: key, **options)
# => {}
```

Accepts:

* `:upload_id` – multipart upload id
* `:key` – object key
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
[Minio]: https://minio.io/
[Client]: #client
[content_disposition]: https://github.com/shrinerb/content_disposition
[`Rack::Request`]: https://www.rubydoc.info/github/rack/rack/master/Rack/Request
[`Aws::S3::Bucket#initialize`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Bucket.html#initialize-instance_method
[`Aws::S3::Client#initialize`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#initialize-instance_method
[`Aws::S3::Client#create_multipart_upload`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#create_multipart_upload-instance_method
[`Aws::S3::Client#list_parts`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#list_parts-instance_method
[`Aws::S3::Client#upload_part`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#upload_part-instance_method
[`Aws::S3::Presigner#presigned_url`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Presigner.html#presigned_url-instance_method
[`Aws::S3::Client#complete_multipart_upload`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#complete_multipart_upload-instance_method
[`Aws::S3::Object#presigned_url`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Object.html#presigned_url-instance_method
[`Aws::S3::Client#get_object`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#get_object-instance_method
[`Aws::S3::Client#abort_multipart_upload`]: https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html#abort_multipart_upload-instance_method
[metadata direct uploads]: https://github.com/shrinerb/shrine/blob/master/doc/metadata.md#direct-uploads
