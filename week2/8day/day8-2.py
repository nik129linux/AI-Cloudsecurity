from __future__ import annotations # Allows using class names in type hints before they are fully defined
import argparse # Import library to parse command-line arguments provided by the user
import json # Import library to handle JSON data serialization and deserialization
import sys # Import library to interact with the Python runtime environment, like exit codes
from dataclasses import dataclass # Import the dataclass decorator to simplify class creation for storing data
from typing import Any, Dict, List, Optional, Tuple # Import types for static type checking annotations
import boto3 # Import the official AWS SDK for Python to interact with AWS services
from botocore.exceptions import BotoCoreError, ClientError # Import specific exceptions to handle AWS API errors

SENSITIVE_PORTS_DEFAULT = [22, 3389, 80, 443] # Define valid ports (SSH, RDP, HTTP, HTTPS) to check for open access by default

@dataclass # Decorator to automatically generate __init__, __repr__, and other methods for the class
class Finding: # Define a class named 'Finding' to structure the data for each security issue found
    region: str # Field to store the AWS region where the security group exists
    group_id: str # Field to store the ID of the security group
    group_name: str # Field to store the human-readable name of the security group
    vpc_id: Optional[str] # Field to store the VPC ID (can be None if not in a VPC)
    direction: str  # inbound # Field to store traffic direction, usually 'inbound' for ingress rules
    protocol: str # Field to store the IP protocol (e.g., tcp, udp, or all)
    from_port: Optional[int] # Field to store the start of the port range (can be None)
    to_port: Optional[int] # Field to store the end of the port range (can be None)
    cidr: str # Field to store the IP range (CIDR block) allowed by the rule
    description: str = "" # Field for the rule's description, defaults to an empty string

def _port_range_overlaps_sensitive(from_port: Optional[int], to_port: Optional[int], sensitive: List[int]) -> bool: # Helper function to check if a rule's port range includes any sensitive ports
 # None can happen for protocols where ports don't apply, or weird/legacy rules.
    if from_port is None or to_port is None: # Check if either start or end port is missing (None)
        return False # Return False because we can't determine overlap without port numbers
    lo = min(from_port, to_port) # Determine the lower bound of the port range
    hi = max(from_port, to_port) # Determine the upper bound of the port range
    return any(lo <= p <= hi for p in sensitive) # Return True if any port in 'sensitive' list falls within [lo, hi] range

def _normalize_proto(ip_protocol: str) -> str: # Helper function to standardize the protocol name string
    # AWS uses "-1" for all protocols. 
    return "all" if ip_protocol == "-1" else ip_protocol.lower() # Return "all" if input is "-1", otherwise return lowercase protocol name

def scan_security_groups(region: str, sensitive_ports: List[int]) -> List[Finding]: # Function to scan SGs in a region for rules exposing sensitive ports
    ec2 = boto3.client("ec2", region_name=region) # Create a low-level client for the EC2 service in the specified region
    findings: List[Finding] = [] # Initialize an empty list to store Finding objects

    paginator = ec2.get_paginator("describe_security_groups") # Create a paginator to handle API responses that span multiple pages
    for page in paginator.paginate(): # Iterate through each page of security group results
        for sg in page.get("SecurityGroups", []): # Iterate through each security group dictionary in the current page
            group_id = sg.get("GroupId", "") # Get the Security Group ID, defaulting to empty string if missing
            group_name = sg.get("GroupName", "") # Get the Security Group Name, defaulting to empty string if missing
            vpc_id = sg.get("VpcId") # Get the VPC ID associated with the group (returns None if missing)

            for perm in sg.get("IpPermissions", []): # Iterate through each inbound permission (rule) in the security group
                proto = _normalize_proto(str(perm.get("IpProtocol", ""))) # Get and normalize the protocol for this rule
                from_port = perm.get("FromPort") # Get the start port number
                to_port = perm.get("ToPort") # Get the end port number

                # IPv4 ranges # Comment indicating the following block handles IPv4 CIDR ranges
                for ipr in perm.get("IpRanges", []): # Iterate through IPv4 ranges defined in this rule
                    cidr = ipr.get("CidrIp") # Get the IPv4 CIDR string (e.g., '0.0.0.0/0')
                    desc = ipr.get("Description") or "" # Get the rule description or verify it defaults to empty string
                    if cidr == "0.0.0.0/0" and _port_range_overlaps_sensitive(from_port, to_port, sensitive_ports): # Check if open to world (IPv4) AND involves sensitive ports
                        findings.append( # Add a new Finding object to the list
                            Finding( # Instantiate the Finding class
                                region=region, # Set the region field
                                group_id=group_id, # Set the group_id field
                                group_name=group_name, # Set the group_name field
                                vpc_id=vpc_id, # Set the vpc_id field
                                direction="inbound", # Set direction to 'inbound'
                                protocol=proto, # Set the protocol field
                                from_port=from_port, # Set the from_port field
                                to_port=to_port, # Set the to_port field
                                cidr=cidr, # Set the cidr field
                                description=desc, # Set the description field
                            ) # Close Finding constructor
                        ) # Close append method

                # IPv6 ranges # Comment indicating the following block handles IPv6 CIDR ranges
                for ip6r in perm.get("Ipv6Ranges", []): # Iterate through IPv6 ranges defined in this rule
                    cidr6 = ip6r.get("CidrIpv6") # Get the IPv6 CIDR string
                    desc6 = ip6r.get("Description") or "" # Get the IPv6 rule description
                    if cidr6 == "::/0" and _port_range_overlaps_sensitive(from_port, to_port, sensitive_ports): # Check if open to world (IPv6) AND involves sensitive ports
                        findings.append( # Add a new Finding object to the list
                            Finding( # Instantiate the Finding class
                                region=region, # Set the region field
                                group_id=group_id, # Set the group_id field
                                group_name=group_name, # Set the group_name field
                                vpc_id=vpc_id, # Set the vpc_id field
                                direction="inbound", # Set direction to 'inbound'
                                protocol=proto, # Set the protocol field
                                from_port=from_port, # Set the from_port field
                                to_port=to_port, # Set the to_port field
                                cidr=cidr6 or "::/0", # Set the cidr field to the found CIDR or default to all IPv6
                                description=desc6, # Set the description field
                            ) # Close Finding constructor
                        ) # Close append method

    return findings # Return the list of all findings gathered

def main() -> int: # Define the main entry point function that returns an integer exit code
    parser = argparse.ArgumentParser(description="Find security groups open to the world on sensitive ports.") # Create an argument parser with a description
    parser.add_argument("--region", default=None, help="AWS region (e.g., us-east-1). If omitted, uses AWS config.") # Add optional --region argument
    parser.add_argument( # Start adding the --ports argument
        "--ports", # Define the flag name as --ports
        default=",".join(map(str, SENSITIVE_PORTS_DEFAULT)), # Set default value by joining the default port list into a comma-string
        help="Comma-separated sensitive ports (default: 22,3389,80,443).", # valid help text
    ) # Close add_argument call
    parser.add_argument("--json", action="store_true", help="Output JSON.") # Add --json flag which, if present, creates a boolean True value
    args = parser.parse_args() # Parse the arguments from command line and store in 'args'

    try: # Start a try block to handle potential value errors
        sensitive_ports = [int(p.strip()) for p in args.ports.split(",") if p.strip()] # Parse the ports string into a list of integers
    except ValueError: # Catch error if conversion to int fails
        print("Error: --ports must be comma-separated integers.", file=sys.stderr) # Print error message to standard error
        return 2 # Return exit code 2 indicating bad usage

    # region resolution: boto3 can infer from env/profile, but we allow override # Comment explaining region selection logic
    session = boto3.session.Session() # Create a boto3 Session to help determine configuration
    region = args.region or session.region_name # Use provided region arg, otherwise fallback to session's configured region
    if not region: # Check if region is still undetermined
        print("Error: No region provided and none configured in AWS profile.", file=sys.stderr) # Print error if no region found
        return 2 # Return exit code 2

    try: # Start a try block for the scanning operation
        findings = scan_security_groups(region, sensitive_ports) # Call the scan logic with the determined region and ports
    except (ClientError, BotoCoreError) as e: # Catch AWS API exceptions
        print(f"AWS API error: {e}", file=sys.stderr) # Print the specific exception message to stderr
        return 1 # Return exit code 1 indicating dynamic runtime error

    if args.json: # Check if the user requested JSON output
        print(json.dumps([f.__dict__ for f in findings], indent=2)) # Convert findings to dictionaries and print as formatted JSON
    else: # If JSON was not requested, print human-readable output
        if not findings: 
            print(f"[OK] No SGs open to 0.0.0.0/0 or ::/0 on ports {sensitive_ports} in {region}.") # Report success/safe state
        else: 
            print(f"[FINDINGS] {len(findings)} risky rule(s) found in {region}:")
            for f in findings: 
                port_str = f"{f.from_port}-{f.to_port}" if f.from_port != f.to_port else f"{f.from_port}" # Format port range (e.g. "80-80" becomes "80")
                extra = f" | {f.description}" if f.description else "" # Format description usage only if it exists
                print( 
                    f"- {f.group_id} ({f.group_name}) VPC={f.vpc_id} " # Print Group ID, Name, VPC
                    f"proto={f.protocol} ports={port_str} cidr={f.cidr}{extra}" # Print protocol, ports, CIDR, and optional description
                ) # Close print call

    # Non-zero exit if findings exist (useful for CI later)
    return 3 if findings else 0 # Return 3 if risks found (fail in CI), otherwise 0 (success)

if __name__ == "__main__": # Check if script is being run directly (not imported)
    raise SystemExit(main()) # Execute main() and use its return value as the system exit code