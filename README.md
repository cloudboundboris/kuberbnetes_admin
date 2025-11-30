### Scripts to scale deployments to 0 and restore back to the same state based on a generated json inventory file by the scale down script. 
#### scale-down-deployments.sh
```
Scale all deployments in a namespace to 0 replicas.
Saves current replica counts to a file for later restoration.

Options:
    -n, --namespace     Kubernetes namespace (required)
    -o, --output        Inventory file path (default: <namespace>-deployment-inventory-<timestamp>.json)
    -d, --dry-run       Show what would be done without making changes
    -h, --help          Show this help message

Examples:
    $(basename "$0") -n production
    $(basename "$0") -n staging -o staging-inventory.json
    $(basename "$0") -n dev --dry-run
```
#### restore-deployments.sh
```
Usage: $(basename "$0") -f <inventory-file> [-d]

Restore deployments to their previous replica counts from an inventory file.

Options:
    -f, --file          Inventory JSON file (required)
    -d, --dry-run       Show what would be done without making changes
    -h, --help          Show this help message

Examples:
    $(basename "$0") -f production-deployment-inventory-20240115-120000.json
    $(basename "$0") -f staging-inventory.json --dry-run
```
