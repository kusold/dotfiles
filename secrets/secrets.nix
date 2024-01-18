let
  mike-mba = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqdsVnaQVVxCbeOJ6Irp2aC5mAFTuXVsbabIYMq9X1I";
#  user2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI6jSq53F/3hEmSs+oq9L4TwOo1PrDMAgcA1uo1CCV/";
  users = [ mike-mba ];

  # ssh-keyscan $HOSTNAME | grep ssh-ed25519
  mallard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG2VPmzg+vmEN38S8Cm0BtcBlV8Y77Vyl+MIFlXFQKcS";
  scannerpi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDAnCLPXfX8FoEDNmeBXk9/24KfT4/+pU9sF2XipGTT/";
  systems = [ mallard scannerpi ];
in
{
  "smb-media-credentials.age".publicKeys = users ++ [ mallard ];
  "smb-scannerpi-credentials.age".publicKeys = users ++ [ scannerpi ];
  "watchlist.txt.age".publicKeys = users ++ systems;
  "notes.age".publicKeys = users;
  "wifi-home.age".publicKeys = users ++ [scannerpi];
  "app-jellyplex-watched.age".publicKeys = users ++ [mallard];
  "user-mike-hashed-passwd.age".publicKeys = users ++ systems;
}