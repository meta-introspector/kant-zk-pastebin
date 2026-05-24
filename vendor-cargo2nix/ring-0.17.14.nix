{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ring
ring
aead_tests
agreement_tests
constant_time_tests
digest_tests
ecdsa_tests
ed25519_tests
error_tests
hkdf_tests
hmac_tests
pbkdf2_tests
quic_tests
rand_tests
rsa_tests
signature_tests";
  version = "0.17.14
1.0.0
0.2.10
0.9
1.2.8
0.52
0.2.155
0.2.148
0.3.37
0.2.148";
  src = ././vendor/ring-0.17.14;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ring
ring
aead_tests
agreement_tests
constant_time_tests
digest_tests
ecdsa_tests
ed25519_tests
error_tests
hkdf_tests
hmac_tests
pbkdf2_tests
quic_tests
rand_tests
rsa_tests
signature_tests";
  #   license = lib.licenses.mit;
  # };
}
