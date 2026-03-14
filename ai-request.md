i would like to create a container image that is a ssh tunnel as a ssh client connect to remote ssh server and setup a ssh tunnel to let other application connnect the container's port that mapping to remote port.

requirements:
- allow setup multiple tunnels
- container not requesting to mount any configure files. the ssh key pair and other configure are all setup by env
- the container also is a helper to help user to : (workflow as following)
  1. gen a new key pair. (ssh-keygen ...) and output the key pair to user.
  2. copy the key to target ssh server (ssh-copy-id ...) . user need to input the host/ip , username (and password) in this step
  3. test/confim the ssh passwordless is work (ssh ... hostname)
  4. at the end, output the guide info how to continue setup the ssh-tunnel (including the ssh server host/ip and username and the key that needed for the ssh tunnel start up):
    a. output the `docker run` command example
    b. output the docker-compose.yaml example
    c. output the helm values.yaml example
- example code docker-compose.yaml
- helm code to under helm. I will later to put it to my helm repo https://github.com/WindoC/helm-charts (https://windoc.github.io/helm-charts)
- create the necessary documents (README.md and codex memory file AGENTS.md)