#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/ENV" ]; then
  set -a
  source "$SCRIPT_DIR/ENV"
  set +a
fi

pipeline="${1:-}"
case "$pipeline" in
  demo|bamtofastq|rnaseq|sarek) ;;
  *)
    echo "usage: $0 {demo|bamtofastq|rnaseq|sarek}" >&2
    exit 2
    ;;
esac

: "${AWS_PROFILE:?set AWS_PROFILE or scripts/ops/ENV}"
: "${AWS_REGION:?set AWS_REGION or scripts/ops/ENV}"

repository="nextflow/$pipeline"
if aws ecr describe-repositories \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --repository-names "$repository" \
  >/dev/null 2>&1; then
  aws ecr describe-repositories \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --repository-names "$repository" \
    --query 'repositories[0].repositoryUri' \
    --output text
  exit 0
fi

: "${ECR_TTL:?set ECR_TTL as DD-MM-YY before creating a repository}"
aws ecr create-repository \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --repository-name "$repository" \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --tags \
    Key=dev,Value=amit \
    Key=project,Value=nextflow-offline \
    Key=created,Value="$(date +%F)" \
    Key=tools,Value=cdx \
    Key=environment,Value=dev \
    Key=owner,Value=amit \
    Key=Name,Value="$repository" \
    Key=version,Value=unversioned \
    Key=TTL,Value="$ECR_TTL" \
    Key=purpose,Value=nextflow-container-mirror \
    Key=phase,Value=offline-distribution \
  --query 'repository.repositoryUri' \
  --output text
