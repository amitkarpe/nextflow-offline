# ECR operator helpers

Create or return one pipeline ECR repository:

```text
AWS_PROFILE=dev AWS_REGION=ap-southeast-1 ECR_TTL=31-12-27 \
  ./scripts/ops/create_ecr.sh sarek
```

Approved pipeline names are `demo`, `bamtofastq`, `rnaseq`, and `sarek`.
Existing repositories are only described. New repositories use immutable tags,
scan on push, and the required project tags. Keep `ENV` local; use
`ENV.example` as its template.
