# 1Password Connect Server + Operator

https://developer.1password.com/docs/connect/get-started/?deploy-type=kubernetes&deploy=kubernetes#step-2-deploy-1password-connect-server

## Deploying

```bash
# Install.sh will download and remove necessary secrets from 1Password
# NOTE: The shell this is run under MUST be authenticated to my 1password account.
$ ./install.sh
```

## Usage

### Reading a Secret

The following provides an example of reading a secret from locally deployed connect server

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  # Create k8s secret called 'some-secret'
  name: some-secret
spec:
  # Read secrets from vault 'lab' with item 'test-secret'
  itemPath: "vaults/lab/items/test-secret"
```

The above produces the following k8s secret fetched by: `kubectl get secret some-secret -o yaml`

```yaml
apiVersion: v1
data:
  password: c3VwZXItc2VjcmV0IQ==
kind: Secret
metadata: ...
```
