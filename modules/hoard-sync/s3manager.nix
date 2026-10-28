# S3 Manager (github.com/cloudlena/s3manager), a small web UI for S3 buckets. Pinned to a release;
# it needs Go 1.27, hence the unstable package set.
{ pkgs }:
(pkgs.buildGoModule.override { go = pkgs.go_1_27; }) {
  pname = "s3manager";
  version = "0.12.0";
  src = pkgs.fetchFromGitHub {
    owner = "cloudlena";
    repo = "s3manager";
    rev = "v0.12.0";
    hash = "sha256-RtzYe5aDhk1ju7h5YMqT/6Wfbvjr904K7vQ3XF1BvyQ=";
  };
  vendorHash = "sha256-sQUUxjCe+j0jYl1gFOjAroE5f6hBCfOn+PLYJtmWmeQ=";
  doCheck = false;
  meta.mainProgram = "s3manager";
}
