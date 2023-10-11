#!/bin/bash
#Use bash to support releases before Catalina.

subp=24
# Read script directory and set output.
#script_dir=$(dirname "$(realpath "$0")")
output="$HOME/Documents/IPScan/output.tsv"
tmp_file="$HOME/Documents/IPScan/tmp.txt"
output_dir=""

#Catch arguments.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--subprocess)
      shift
      if [[ $# -gt 0 ]]; then
        subp="$1"
      fi
      ;;
    -o|--output_directory)
      shift
      if [[ $# -gt 0 ]]; then
        output_dir="$1"
      fi
      ;;
    *)
      break
      ;;
  esac
  shift
done

#Check if ouput directory is specified. Otherwise use default.
if [ -n "$output_dir" ]; then
  #script_dir="$output_dir"
  output="$output_dir/output.tsv"
  tmp_file="$output_dir/tmp.txt"
  mkdir output_dir
else
  mkdir $HOME/Documents/IPScan
fi
touch output && touch tmp_file
#Function to ping IPs. Function is used to allow for concurrent subprocesses. Output is written into temp file.
ping_ip() {
  local ip="$1"
  if ! ping -c 4 -W 2 "$ip" &> /dev/null; then
    echo "Free IP: $ip"
    echo 1 $ip >> $tmp_file
    ((count--))
  else
    echo "IP in use: $ip"
    echo 0 $ip >> $tmp_file
    ((count--))
  fi
}

#Determine outgoing interface.
interface=$(route get 1.1.1.1 | awk '/interface:/ {print $2}')

if [ -n "$interface" ]; then
    #Read IP & Subnet
    ipv4=$(ipconfig getifaddr $interface)
    subnet=$(ipconfig getsummary $interface | awk '/subnet_mask/ {print $3}')
    subnet_cidr=$(echo $subnet | awk -F'.' '{for(i=1;i<=NF;i++) s+=8-length($i); print s}')

    # Extract octets via input field separator (IFS) and construct network range via bitwise 'AND' & 'OR' with binary inverse of subnet mask. 
    IFS=. read -r i1 i2 i3 i4 <<< "$ipv4"
    IFS=. read -r m1 m2 m3 m4 <<< "$subnet"
    net_range_start="$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$((i4 & m4))"
    broadcast="$((i1 | ~m1 & 255)).$((i2 | ~m2 & 255)).$((i3 | ~m3 & 255)).$((i4 | ~m4 & 255))"

    echo "Scanning network for $ipv4/$subnet_cidr"
    echo "Network Range Start: $net_range_start"
    echo "Broadcast Address: $broadcast"

    #Generate individual IPs, feed them to an array and loop through total number of IPs to generate all octets in range. First and last IP in range is skipped.
    num_ips=$((2**(32 - subnet_cidr)))
    echo "Number of scanned IPs: $(($num_ips-1))"
    ip_array=()
    for ((i = 1; i < num_ips; i++)); do
      ip_octet1=$((i1 & m1 | (i >> 24 & 255)))
      ip_octet2=$((i2 & m2 | (i >> 16 & 255)))
      ip_octet3=$((i3 & m3 | (i >> 8 & 255)))
      ip_octet4=$((i4 & m4 | (i & 255)))
      ip_array+=("$ip_octet1.$ip_octet2.$ip_octet3.$ip_octet4")
    done

    #Ping each IP address in background, and maintain number of subprocesses via "count"
    count=0
    > $script_dir/tmp.txt
    for ip in "${ip_array[@]}"; do
      while [ $count -ge $subp ]; do
        wait
        count=0
      done
      (ping_ip "$ip") &
      ((count++))
    done
    wait

    #Read temp file and and feed into arrays.
    free_ip=()
    used_ip=()
    while read -r line; do
    fields=($line)
    if [[ ${fields[0]} == "1" ]]; then
        free_ip+=(${fields[1]})
    elif [[ ${fields[0]} == "0" ]]; then
        used_ip+=(${fields[1]})
    fi
    done < "$tmp_file"

    variables=("Network Interface" "Host" "Subnet" "Subnet CIDR" "Scan Range Start" "Broadcast" "Total number of IPs" "Threads")
    values=("$interface" "$ipv4" "$subnet" "$subnet_cidr" "$net_range_start" "$broadcast" "$num_ips" "$subp")

    # Calculate max n rows and sort arrays into tsv.
    rows_tmp=$(( ${#free_ip[@]} > ${#used_ip[@]} ? ${#free_ip[@]} : ${#used_ip[@]} ))
    rows=$(( $rows_tmp > ${#values[@]} > rows ? $rows_tmp : ${#values[@]} ))
    echo -e "Network\tAddress\tFree\tUsed" > "$output"

    for ((i = 0; i < rows; i++)); do
        var_i=""
        val_i=""
        var_i="${variables[i]}"
        val_i="${values[i]}"
        free_ip_i="${free_ip[i]}"
        used_ip_i="${used_ip[i]}"
        echo -e "$var_i\t$val_i\t$free_ip_i\t$used_ip_i" >> "$output"
    done

    echo "Output written to $output"
else
  echo "Unable to determine outgoing interface. Check internet connection."
fi
