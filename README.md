# Scan Container Image

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Scan%20Container%20Image-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/scan-container-image)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A GitHub Action to scan container images for vulnerabilities and secrets with [Trivy](https://github.com/aquasecurity/trivy), reporting the findings in the job summary. Non-blocking by default: it warns the team without stopping the pipeline, and can be turned into a gate when the image is clean.

## Features

- **Non-Blocking by Default**: Findings become a warning annotation and a table in the job summary; set `fail-on-findings: 'true'` to block
- **No Install Needed**: Runs Trivy through Docker (`aquasec/trivy`), so it works on GitHub-hosted and self-hosted runners with Docker
- **Any Registry**: ECR, GHCR, Docker Hub or any registry the runner is logged in to, or images built in the same job
- **Actionable Results**: Reports only vulnerabilities that already have a fix by default (`ignore-unfixed`)
- **Secret Detection**: Scans image layers for leaked credentials (`scanners: vuln,secret`)
- **Ignore List**: Accepts a `.trivyignore` file for accepted risks
- **Outputs**: Finding counts and an optional JSON report for artifacts or further processing

## Prerequisites

### Docker

The runner needs Docker. GitHub-hosted Linux runners already have it.

### Registry Access

For private images, log in before the scan (e.g. `docker/login-action` or `aws-actions/amazon-ecr-login`) or pass `registry-username`/`registry-password`. For an image built in the same job and loaded into the local Docker daemon, set `pull: 'false'`.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `image` | Image to scan | Yes | - |
| `severity` | Comma-separated severities to report | No | `HIGH,CRITICAL` |
| `ignore-unfixed` | Report only vulnerabilities that already have a fixed version | No | `true` |
| `scanners` | Comma-separated Trivy scanners (`vuln`, `secret`, `misconfig`, `license`) | No | `vuln,secret` |
| `fail-on-findings` | Fail the step when findings are reported. `false` = only warn | No | `false` |
| `ignore-file` | Path to a `.trivyignore` file, relative to the workspace | No | `''` |
| `pull` | Pull the image before scanning | No | `true` |
| `registry-username` | Registry username (leave empty if already logged in) | No | `''` |
| `registry-password` | Registry password or token | No | `''` |
| `trivy-version` | Trivy version (`aquasec/trivy` image tag) | No | `0.72.0` |
| `summary` | Write the findings table to the job summary | No | `true` |
| `output` | Path to save the JSON report, relative to the workspace | No | `''` |

## Outputs

| Output | Description |
|--------|-------------|
| `findings` | Total number of findings (vulnerabilities + secrets) |
| `critical` | Number of CRITICAL findings |
| `high` | Number of HIGH findings |
| `report` | Path to the JSON report (only when `output` is set) |

## Usage

### Basic Example (non-blocking)

```yaml
jobs:
  image-scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read
    steps:
      - name: Login to GHCR
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Scan image
        uses: kubescript/scan-image@v1
        with:
          image: ghcr.io/${{ github.repository_owner }}/my-app:${{ github.sha }}
```

### Amazon ECR

```yaml
jobs:
  image-scan:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v6

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions
          aws-region: us-east-1

      - name: Login to ECR
        uses: docker/login-action@v4
        with:
          registry: 123456789012.dkr.ecr.us-east-1.amazonaws.com

      - name: Scan image
        uses: kubescript/scan-image@v1
        with:
          image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:${{ github.sha }}
          ignore-file: .trivyignore
```

### Security Gate (blocking)

Once the image is clean, block new HIGH/CRITICAL findings:

```yaml
- name: Scan image
  uses: kubescript/scan-image@v1
  with:
    image: ghcr.io/my-org/my-app:${{ github.sha }}
    fail-on-findings: 'true'
```

### Image Built in the Same Job

```yaml
- name: Build
  run: docker build -t my-app:${{ github.sha }} .

- name: Scan image
  uses: kubescript/scan-image@v1
  with:
    image: my-app:${{ github.sha }}
    pull: 'false'
```

### Keep the Report as an Artifact

```yaml
- name: Scan image
  id: scan
  uses: kubescript/scan-image@v1
  with:
    image: ghcr.io/my-org/my-app:${{ github.sha }}
    severity: MEDIUM,HIGH,CRITICAL
    output: reports/trivy.json

- name: Upload report
  if: steps.scan.outputs.findings != '0'
  uses: actions/upload-artifact@v4
  with:
    name: trivy-report
    path: reports/trivy.json
```

## Troubleshooting

### Error: `Docker not found on the runner`

The action runs Trivy as a container. Use a runner with Docker (GitHub-hosted Linux runners have it).

### Error: `unauthorized` or `pull access denied`

The runner is not logged in to the image registry. Add a login step before the scan or pass `registry-username`/`registry-password`. For images built in the same job, set `pull: 'false'`.

### Too many findings from the base image

Most findings usually come from the OS packages of the base image. Prefer slim or distroless bases, keep them updated, and remove tools not used at runtime (package managers, shells). Accepted risks go into a `.trivyignore` file.

### Summary truncated

The job summary accepts up to 1 MiB per step. For large reports, set `output` and upload the JSON as an artifact.

## Acknowledgments

This action uses [Trivy](https://github.com/aquasecurity/trivy) by Aqua Security.

Thank you to all the maintainers and contributors of the Trivy project!

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Support

- Report issues: [GitHub Issues](https://github.com/kubescript/scan-image/issues)
- Documentation: [GitHub Marketplace](https://github.com/marketplace/actions/scan-container-image)
- Trivy Docs: [https://trivy.dev](https://trivy.dev)

---

Made with ❤️ by [KubeScript](https://github.com/kubescript)
