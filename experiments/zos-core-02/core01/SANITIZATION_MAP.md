# Sanitization map

Archive of origin SHA-256

`c5a660235ce00d6e463c988e709683ed35d0d45f17cf0855ea0a9b15486f6b0a`

The table covers all 60 original regular files, including the original manifest. Paths are relative to the original archive root directory. Five source or report files are derived, nine files are copied byte for byte, and 46 original files are omitted.

New release files are PUBLICATION_REPORT.md, SANITIZATION_MAP.md, REPRODUCTION.md, SECURITY_LIMITATIONS.md, package.sh, PUBLIC_MANIFEST.sha256, rebuild/PUBLIC_INPUTS.sha256, and the evidence directory. These files have no direct original counterpart. Evidence contains the new execution outputs. The new command transcript replaces configured tool and runtime paths with labels. The independent verification log replaces the OpenSSL per-process diagnostic prefix with a placeholder. The test stdout/stderr, summary, descriptor, message, signature and public keys are exported from the new run. The artifact comparison file records hashes for the six files compared byte for byte with the historical run. The private keys and fresh Rust executable were confined to the temporary runtime and removed during cleanup.

| Original path | Original SHA-256 | Public disposition |
|---|---|---|
| `FINAL_REPORT.md` | `c1c333bd57a66d8ffbed4de456c70abc7a4badd962ee50e3bdd0a1c9679608bf` | Derived as `HISTORICAL_REPORT.md` (Label as historical derivative and replace private lab path.) |
| `MANIFEST.sha256` | `06732a160058357179411b13ed5d42ce1d60fba3db6c5a0ace39be0537b7cae1` | Omitted. Superseded by PUBLIC_MANIFEST.sha256. |
| `intake/CORE-01B-MANIFEST.sha256` | `33172f82f47a3d262b3efdcbe05a3822a5cea5a436d4f739d3a503c63b480de6` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `intake/FINAL_REPORT.md` | `e6a35c5cda4255e1694899fe7e73d7aceab14ef6b2d707d979ad10cee037b9d5` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `intake/SECURITY_GAPS.md` | `f70255eb7ddacfa6273f8cd467694041830cd1da6fdcf78922f44ae7637bcca5` | Omitted. Summarized in SECURITY_LIMITATIONS.md. |
| `intake/TEST_MATRIX.md` | `086583f9166aac78bffdea310b48b267a423e71101c2ec037c7fb2697df8ba19` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `intake/fixtures/Check.lean` | `cd093a3540fba34c53c980c18920b2bdddda2753cf37ad8170243938f4c21edd` | Retained byte for byte. |
| `intake/fixtures/Good.lean` | `df70151090e05f2d444acce3ad5bd10f9eb9e6408c30aafe2c9152ab997e1a5a` | Retained byte for byte. |
| `intake/fixtures/Invalid.lean` | `06774498c9963d86aa2bdacc06628082f1b094ca12f9a27605085dfe36704c35` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `intake/fixtures/Mismatch.lean` | `6428341c0fe1510bac76621204d6aabd583e4c87fb10cd81929c2e5c24533712` | Retained byte for byte. |
| `intake/fixtures/Ref.lean` | `d2d8c48b114a77d39f503bd4089dd6308fe4f7f692005f194024fbbe508621cc` | Retained byte for byte. |
| `intake/fixtures/SorryCase.lean` | `46f2d644067cdac9b757d8eb56d44dfd0709c676a1a741c6531656762a4d8912` | Retained byte for byte. |
| `intake/run.py` | `7b1301feab3dc172ea235f91e0b0b26cfd0f40df21e7b47194c93fa023acf68e` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `intake/source/Invalid.lean` | `06774498c9963d86aa2bdacc06628082f1b094ca12f9a27605085dfe36704c35` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `intake/source/seam.rs` | `522f9cf4db2421746e11b810028797d5df211d519cbe7f20c440e352f7ebbad6` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `intake/source/seam_step2.rs` | `5b3922d93c5657af5e53dc96ba2102b3308456bfe3b8be7ab4710fb63d21606c` | Omitted. Historical intake material or duplicate source. The public build stages the verified final inputs. |
| `logs/artifact-comparison.log` | `2c3731c025735aaa20faff47ca9a63e4c32c53f3672e9d793995e2f56ecded49` | Omitted. Historical log. Source hashes and results are carried by the public derivative and fresh evidence. |
| `logs/core01b-after.log` | `94ad793b2c9ae3d242d8e125c1763518cab74186af3ca532059051f64eb859cd` | Omitted. Historical log. Source hashes and results are carried by the public derivative and fresh evidence. |
| `logs/core01b-intake.log` | `94ad793b2c9ae3d242d8e125c1763518cab74186af3ca532059051f64eb859cd` | Omitted. Historical log. Source hashes and results are carried by the public derivative and fresh evidence. |
| `logs/independent-verification.log` | `edf847050218f1747ae67f65214742f490de5c03063ce5472a8c5c84a61e99ba` | Omitted. Historical log. Source hashes and results are carried by the public derivative and fresh evidence. |
| `logs/isolation.log` | `f18e9fc11541cba4920d1eb9ce821d23898ad075767844c2e247265ecdcd99cb` | Omitted. Historical log. Source hashes and results are carried by the public derivative and fresh evidence. |
| `logs/jobverifier-provenance.log` | `425ec0a2304ab8a69cc94d3850a0f4e9dbb63ae8be28373cee5c85ac430bbde8` | Omitted. Historical log. Source hashes and results are carried by the public derivative and fresh evidence. |
| `logs/trace-probe.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | Omitted. Historical log. Source hashes and results are carried by the public derivative and fresh evidence. |
| `package.sh` | `d3a47d99b3dfffa06b8b903a737548bd6d081f5308d6205961e0f873c9b6a7f0` | Omitted. Superseded by the public snapshot packager. |
| `rebuild/DAO_CONSUMER_DESIGN.md` | `63e0d2a404414271e353d91c4c6be1cd3dc7ef925530948d079094aee7c8a448` | Retained byte for byte. |
| `rebuild/RUST_ADAPTER_DESIGN.md` | `b3823068259d73a79545e9f99ed5ad4fd3b0c6db6b6e5159487175f5d0433217` | Omitted. Relevant limitations summarized in SECURITY_LIMITATIONS.md. |
| `rebuild/SECURITY_GAPS.md` | `f70255eb7ddacfa6273f8cd467694041830cd1da6fdcf78922f44ae7637bcca5` | Omitted. Summarized in SECURITY_LIMITATIONS.md. |
| `rebuild/SOURCE_IDENTITY.md` | `6830fbf0c4b3127ea0df88d984046c2365e95d51548aca53e5f79cb71c4a7b27` | Derived as `rebuild/SOURCE_IDENTITY.md` (Remove checkout and prior run paths, clarify provenance checks, record corrected SorryCase blob.) |
| `rebuild/STEP1_INPUTS.sha256` | `5952ddfe2f7bc735a38cf932ef709486bd55155bc7da9d4eadad84ca3ae27efe` | Omitted. Superseded by rebuild/PUBLIC_INPUTS.sha256 for the actual public build inputs. |
| `rebuild/TEST_MATRIX.md` | `086583f9166aac78bffdea310b48b267a423e71101c2ec037c7fb2697df8ba19` | Omitted. Superseded historical design, test plan or inactive source. |
| `rebuild/VERIFICATION_CONTRACT.md` | `f350c952ff3b74bff327b00cd47564f0bdeeeaad6c40ea1222fca4de0e1675c6` | Retained byte for byte. |
| `rebuild/evidence-d30tdiz_/Check.lean` | `cd093a3540fba34c53c980c18920b2bdddda2753cf37ad8170243938f4c21edd` | Omitted. Duplicate build input. The reproduction source is listed separately. |
| `rebuild/evidence-d30tdiz_/Good.lean` | `df70151090e05f2d444acce3ad5bd10f9eb9e6408c30aafe2c9152ab997e1a5a` | Omitted. Duplicate build input. The reproduction source is listed separately. |
| `rebuild/evidence-d30tdiz_/Good.olean` | `56a7ed934806d8f6e33bd3d938a325761e741dbe534f6e295dc9901d8296a52b` | Omitted. Generated Lean artifact. Rebuilt locally and compared by digest. |
| `rebuild/evidence-d30tdiz_/Invalid.lean` | `06774498c9963d86aa2bdacc06628082f1b094ca12f9a27605085dfe36704c35` | Omitted. Duplicate build input. The reproduction source is listed separately. |
| `rebuild/evidence-d30tdiz_/Mismatch.lean` | `6428341c0fe1510bac76621204d6aabd583e4c87fb10cd81929c2e5c24533712` | Omitted. Duplicate build input. The reproduction source is listed separately. |
| `rebuild/evidence-d30tdiz_/Mismatch.olean` | `c68c16ff71a7ac413c46045991da0ae6aabfac5b37f2f78ac6996776e9805cd0` | Omitted. Generated Lean artifact. Rebuilt locally and compared by digest. |
| `rebuild/evidence-d30tdiz_/Ref.lean` | `d2d8c48b114a77d39f503bd4089dd6308fe4f7f692005f194024fbbe508621cc` | Omitted. Duplicate build input. The reproduction source is listed separately. |
| `rebuild/evidence-d30tdiz_/Ref.olean` | `39987ad253f828a8c80d080440bf342aeea4d53757f10c00bf24de33aee36174` | Omitted. Generated Lean artifact. Rebuilt locally and compared by digest. |
| `rebuild/evidence-d30tdiz_/SorryCase.lean` | `46f2d644067cdac9b757d8eb56d44dfd0709c676a1a741c6531656762a4d8912` | Omitted. Duplicate build input. The reproduction source is listed separately. |
| `rebuild/evidence-d30tdiz_/SorryCase.olean` | `a9e2448de0d06a0bf4ea4d9eaba29101c6e6f6bfe31e9ce2ae1f8df662c80a79` | Omitted. Generated Lean artifact. Rebuilt locally and compared by digest. |
| `rebuild/evidence-d30tdiz_/commands.jsonl` | `a40d18b85cb8eac992725fd3ec29c2d02ee1f6d528606a68006ea110d17da716` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/descriptor.txt` | `97d9f3ed8049310a022cc20ec58a9ec19717e5eaebb16a83e6a9a4f7239d1f7c` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/message.bin` | `e890dc3df4a43affbcbdfec09e1cfadb6adb1d10cc79c160914c5f21ddb406be` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/other-public.pem` | `d29913a328afd377ef445ade072ed085de64275173f24aa65dad49a61b10b904` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/seam` | `8b3cfd258b4e11d59edacb77242af0e37f3c9faebaf8438f62ed97c9b75b6d8a` | Omitted. Compiled Rust executable containing local paths. Excluded without editing its bytes. |
| `rebuild/evidence-d30tdiz_/seam.rs` | `6c6c0c9c3e99b078aef02225d35f99a7a0c1e54e37bc6c13550839370fa6442a` | Omitted. Duplicate build input. The reproduction source is listed separately. |
| `rebuild/evidence-d30tdiz_/signature.bin` | `8b83decb5a0154174f24079fa2a63f3ea0e25801a0c6f5e516904cc62628f148` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/summary.json` | `7e0651881ce77eb2b847782fd50fd395954565ed242cfcabcce433069ce6824d` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/tests.stderr.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/tests.stdout.log` | `9d63e30a2cc4d3b049b99e05cb499d4f496dd1d2a3f48f35165e3e35a91a9449` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/evidence-d30tdiz_/trusted-public.pem` | `dfc7e792219075623ec7063ec5f7d1dc83af5d7eb4a7f90f608d4cb7dc0aa49a` | Omitted. Historical execution export. Public evidence comes from the fresh rebuild. |
| `rebuild/isolate.py` | `530234446a6e336ab814bc41766484322d33071b80cb9792e3273b68e47df245` | Derived as `rebuild/isolate.py` (Pass resolved tool settings into contained child, suppress package root in log and specify packed ABI layout.) |
| `rebuild/run.py` | `ed77782deb743a5202a0b91d88b871a265bbedb1c727e087573e3648de0c94f2` | Derived as `rebuild/run.py` (Use configured tool paths, explicit tool identity checks and public input manifest. Normalize transcript paths and omit executable exports. Drop historical Step 1 adapter check.) |
| `rebuild/source/Invalid.lean` | `06774498c9963d86aa2bdacc06628082f1b094ca12f9a27605085dfe36704c35` | Retained byte for byte. |
| `rebuild/source/seam.rs` | `522f9cf4db2421746e11b810028797d5df211d519cbe7f20c440e352f7ebbad6` | Omitted. Superseded historical design, test plan or inactive source. |
| `rebuild/source/seam_step2.rs` | `6c6c0c9c3e99b078aef02225d35f99a7a0c1e54e37bc6c13550839370fa6442a` | Derived as `rebuild/source/seam_step2.rs` (Resolve Lean via launcher environment and use its controlled PATH for checker subprocesses. Preserve descriptor field order and checks.) |
| `rebuild/verify.py` | `b4d77df6202a71da4f0228b51914687f5cad9f0e4bb48d636e6ac1835b0078c2` | Retained byte for byte. |
| `runner.patch` | `a545f7ef174d477e4d5b6baae818090125da3ad4b1f4fd74548469035de057be` | Omitted. Historical patch contains private paths. The public derivative and this map identify the replacement. |
| `source-path.patch` | `fe2f2083f49eda7ba40da7b056a389da476a7268de075659874fcf06b4582e45` | Omitted. Historical patch contains private paths. The public derivative and this map identify the replacement. |
