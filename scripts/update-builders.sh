for ((i=0;i<10;i++))
do
    scp builder-config/configuration.nix builder-${i}:/etc/nixos/ && ssh builder-${i} -t nixos-rebuild switch
done
