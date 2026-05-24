{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "utoipa-gen
utoipa_gen
common
modify_test
openapi_derive
openapi_derive_test
path_derive
path_derive_actix
path_derive_auto_into_responses
path_derive_auto_into_responses_actix
path_derive_auto_into_responses_axum
path_derive_axum_test
path_derive_rocket
path_parameter_derive_actix
path_parameter_derive_test
path_response_derive_test
request_body_derive_test
response_derive_test
schema_derive_test
utoipa_gen_test";
  version = "4.3.1
1.0
1.0
1.0
1.7
2.0
1
2
1
4
2
0.7
0.4
1
0.5
1
1
1
3.0
1.10
0.3";
  src = ././vendor/utoipa-gen-4.3.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "utoipa-gen
utoipa_gen
common
modify_test
openapi_derive
openapi_derive_test
path_derive
path_derive_actix
path_derive_auto_into_responses
path_derive_auto_into_responses_actix
path_derive_auto_into_responses_axum
path_derive_axum_test
path_derive_rocket
path_parameter_derive_actix
path_parameter_derive_test
path_response_derive_test
request_body_derive_test
response_derive_test
schema_derive_test
utoipa_gen_test";
  #   license = lib.licenses.mit;
  # };
}
