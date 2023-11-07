{ pkgs, inputs, ... }:
{
  users.users.mkusold = {
    name = "mkusold";
    home = "/Users/mkusold";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9Gr/FM9ZbYxHm8pULpsvAhCsJj1AGYP+BVNU2hR1awY77KyOPu95elA2kfi2+0n0sl2gK9yeU2GwfS+L9SkZxEl5Tw8nzac1DZ07KU0GVnORkXMPjnkSKMtUKahmRYzAQCtgcflLhTDL5HAAcIhdFGGnnGtGscoYXqTaWkCf8mQTshIaG3XPGT1nxk2qJDPl8Svaw4RLnQ1hKZLR2BoJO911hhXnlWRpIp+3O+sYqglM63mHFtO6m4IeUwfmO9VF90TTysP2dAPrHXH1Yz1gYwg0JuaWohUs7DJM9255r13Mt++MKy5F+Owuv855Bl99xY3fB2TgZ9hDrQRZV8qJ9W7WvJZNWIuuCkfOfIBKIJNtx95qdGPN41FbHNX7rBwwVH/SHPpIDEfUeOW+80lL2xNIZINMQzFnsX6cqT1s+p7nu3bI5kSFydcEz1Of5CUTEVex2q3bErOxzDSNAVXgGy9gzSRsesAxI50cTswR8vU7YGQphrWN0tgduSxN3tcM="
    ];
  };
}