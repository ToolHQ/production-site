#! /bin/bash

oci compute image list \
  --compartment-id "ocid1.tenancy.oc1..aaaaaaaabfg4pvm7softb3hmorwr4vntjv7qikjttjcughvcsqs27k2k2eqa" \
  --operating-system "Canonical Ubuntu" \
  --operating-system-version "24.04" \
  --shape "VM.Standard.A1.Flex" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --region us-ashburn-1
