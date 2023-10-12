# IPSCanBash
Quick Bash Script to scan the range of available addresses within the hosts LAN, relying on tools that should be available on an unmodified macOS System.

Outputs a tsv file with basic parameters and a list of Free and Used IPs of the local network.
Use -o/--output_directory to change the output directory. By default the script launches 24 concurrent pings, you can change this behaviour via -s/--subprocess
