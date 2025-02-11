# project2-staticwebsite-terraform

(learning process-> did everything manually using the UI then starting working on this TF code)

This is a basic project:

1. Terraform to create Amazon AWS resources: (S3 storage, Cloudfront, Certificate request, CodePipeline, git hub connection)
3. index.html exists on the repository: https://github.com/adamlevi87/project2-staticwebsite-content/blob/main/README.md
4. Upon any change to this repository: index.html will be pushed by the CodePipeline to the S3 storage which the Cloudfront service exposes.
