{
  description = "Temporary flake to get git sha256";
  outputs = { self, ... }: {
    defaultPackage.x86_64-linux = builtins.fetchGit {
      url = "/mnt/data1/kant/pastebin";
      rev = "d8d1e1dd33e3f4f5c8b547e34824211987401557";
    };
  };
}