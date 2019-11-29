# MetalScan

* Blelloch's exclusive scan algorithm, implemented in Metal and Swift.
* Arbitrary input size, specifically:
  * Input size is not required to be a power of 2.
  * Input size is not bounded by `maxTotalThreadsPerThreadgroup` of a single threadgrouop.

## Notes

I haven't figured out yet how to run the unit tests for a static library that uses Metal. (When I did that, I failed at making a new `MTLLibrary` from device.) Therefore this is done as an app. 

To use the exclusive scan functionality, just copy `ExclusiveScan.swift` and `Scan.metal` to your own project.
