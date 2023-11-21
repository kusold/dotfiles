let
  mike-mba = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqdsVnaQVVxCbeOJ6Irp2aC5mAFTuXVsbabIYMq9X1I";
#  user2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI6jSq53F/3hEmSs+oq9L4TwOo1PrDMAgcA1uo1CCV/";
  users = [ mike-mba ];

  mallard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG2VPmzg+vmEN38S8Cm0BtcBlV8Y77Vyl+MIFlXFQKcS";
  systems = [ mallard ];
in
{
  "smb-media-credentials.age".publicKeys = users ++ [ mallard ];
  "watchlist.txt.age".publicKeys = users ++ systems;
  "notes.age".publicKeys = users;
}