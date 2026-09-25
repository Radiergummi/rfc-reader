# Schema

The RELAX NG schema for RFCXML v3, as xml2rfc ships it: `v3.rng` and the `SVG-1.2-RFC.rng` it includes, copied unchanged from [`ietf-tools/xml2rfc`](https://github.com/ietf-tools/xml2rfc) at `xml2rfc/data/`, commit `9c796f9458c0b8844c7056a4d9894318ed0857e0` (10 September 2026). `v3.rng` is the compiled form of the `rfc7991bis.rnc` that authors.ietf.org calls authoritative.

`corpus-build convert --schema v3.rng` validates every document it writes against it with `xmllint --relaxng` and records why a document fails in `report.json` (`SchemaCheck.swift`). `make corpus-schema-control` is the control: RFCs 8999, 9113 and 9220 as the RFC Editor published them must validate.

To update, copy both files from a newer xml2rfc commit, record the commit here, and run the control and a full `make corpus-convert` before and after.
