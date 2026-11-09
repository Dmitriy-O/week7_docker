from pathlib import Path
import re
import sys

import yaml


class UniqueLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node):
    result = {}

    for key_node, value_node in node.value:
        key = loader.construct_object(key_node)

        if key in result:
            raise ValueError("duplicate YAML key")

        result[key] = loader.construct_object(value_node)

    return result


UniqueLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    unique_mapping,
)


def encrypted(value):
    return isinstance(value, str) and re.fullmatch(
        r"ENC\[AES256_GCM,data:[^,]+,iv:[^,]+,tag:[^,]+,type:str\]",
        value,
    ) is not None


def check_file(path):
    document = yaml.load(path.read_text(), Loader=UniqueLoader)

    if not isinstance(document, dict):
        raise ValueError("expected a YAML mapping")

    if set(document) != {"secrets", "sops"}:
        raise ValueError("expected secrets and sops sections")

    secrets = document["secrets"]

    if not isinstance(secrets, dict):
        raise ValueError("expected a secrets mapping")

    if not {"DB_PASSWORD", "SECRET_KEY"} <= set(secrets):
        raise ValueError("required secret fields are missing")

    if not all(encrypted(value) for value in secrets.values()):
        raise ValueError("secret values must be encrypted with SOPS")

    metadata = document["sops"]

    if not isinstance(metadata, dict):
        raise ValueError("SOPS metadata is missing")

    if not encrypted(metadata.get("mac")):
        raise ValueError("encrypted SOPS MAC is missing")

    if not metadata.get("age"):
        raise ValueError("SOPS age recipients are missing")


def main():
    root = Path("k8s_django_deployment_task/environments")
    environments = sorted(root.glob("*/values.yaml"))

    if not environments:
        raise SystemExit("FAIL: no environments found")

    for values in environments:
        path = values.parent / "secrets.enc.yaml"

        try:
            check_file(path)
        except (OSError, ValueError, yaml.YAMLError):
            print(
                f"FAIL: {path}: invalid SOPS file or plaintext values",
                file=sys.stderr,
            )
            return 1

        print(f"PASS: {path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
