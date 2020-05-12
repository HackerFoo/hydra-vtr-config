# run as root and as hydra-queue-runner to check connections
for ((i=0;i<10;i++))
do
    nix ping-store --store ssh://root@builder-${i}
done
