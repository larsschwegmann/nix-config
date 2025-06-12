{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7HENJ0Y311803A";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "128M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ]; # Override existing partition
                # Subvolumes must set a mountpoint in order to be mounted,
                # unless their parent is mounted
                subvolumes = {
                  # Subvolume name is different from mountpoint
                  "/rootfs" = {
                    mountpoint = "/";
                  };
                  # Subvolume name is the same as the mountpoint
                  "/home" = {
                    mountOptions = [ "compress=zstd" ];
                    mountpoint = "/home";
                  };
                  # Sub(sub)volume doesn't need a mountpoint as its parent is mounted
                  # "/home/user" = { };
                  # Parent is not mounted so the mountpoint must be set
                  "/nix" = {
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                    mountpoint = "/nix";
                  };
                  # This subvolume will be created but not mounted
                  # "/test" = { };
                  # Subvolume for the swapfile
                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap = {
                      swapfile.size = "32G";
                    };
                  };
                  # mountpoint for games etc
                  "/media/nvme1" = {
                    mountpoint = "/media/nvme1";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                };

                mountpoint = "/nvme1-partition-root";
                swap = {
                  swapfile = {
                    size = "32G";
                  };
                };
              };
            };
          };
        };
      };
       
      extra = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Sabrent_Rocket_4.0_1TB_BEC00715077500101430";
        content = {
          type = "gpt";
          partitions = {
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/media/nvme2" = {
                    mountpoint = "/media/nvme2";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                };
                mountpoint = "/nvme2-partition-root";
              };
            };
          };
        };
      };
    };
  };
}
