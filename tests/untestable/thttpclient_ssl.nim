#
#
#            Nim - SSL integration tests
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## Warning: this test performs external networking.
## Test with:
## ./bin/nim c -d:ssl -p:. --threads:on -r tests/untestable/thttpclient_ssl.nim
##
## See https://github.com/FedericoCeratto/ssl-comparison/blob/master/README.md
## for a comparison with other clients.

import
  httpclient,
  net,
  strutils,
  threadpool,
  unittest


type
  # bad and dubious tests should not pass SSL validation
  # "_broken" mark the test as skipped while checking that it is
  # really failing
  Category = enum
    good, bad, dubious, good_broken, bad_broken, dubious_broken
  CertTest = tuple[url:string, category:Category, desc: string]

const certificate_tests: array[0..55, CertTest] = [
  ("https://wrong.host.badssl.com/", bad, "wrong.host"),
  ("https://captive-portal.badssl.com/", bad, "captive-portal"),
  ("https://expired.badssl.com/", bad, "expired"),
  ("https://google.com/", good, "good"),
  ("https://self-signed.badssl.com/", bad, "self-signed"),
  ("https://untrusted-root.badssl.com/", bad, "untrusted-root"),
  ("https://revoked.badssl.com/", bad_broken, "revoked"),
  ("https://pinning-test.badssl.com/", bad_broken, "pinning-test"),
  ("https://no-common-name.badssl.com/", dubious_broken, "no-common-name"),
  ("https://no-subject.badssl.com/", dubious_broken, "no-subject"),
  ("https://incomplete-chain.badssl.com/", dubious, "incomplete-chain"),
  ("https://sha1-intermediate.badssl.com/", bad_broken, "sha1-intermediate"),
  ("https://sha256.badssl.com/", good, "sha256"),
  ("https://sha384.badssl.com/", good, "sha384"),
  ("https://sha512.badssl.com/", good, "sha512"),
  ("https://1000-sans.badssl.com/", good, "1000-sans"),
  ("https://10000-sans.badssl.com/", good_broken, "10000-sans"),
  ("https://ecc256.badssl.com/", good, "ecc256"),
  ("https://ecc384.badssl.com/", good, "ecc384"),
  ("https://rsa2048.badssl.com/", good, "rsa2048"),
  ("https://rsa8192.badssl.com/", dubious_broken, "rsa8192"),
  ("http://http.badssl.com/", good, "regular http"),
  ("https://http.badssl.com/", bad_broken, "http on https URL"),  # FIXME
  ("https://cbc.badssl.com/", dubious_broken, "cbc"),
  ("https://rc4-md5.badssl.com/", bad, "rc4-md5"),
  ("https://rc4.badssl.com/", bad, "rc4"),
  ("https://3des.badssl.com/", bad, "3des"),
  ("https://null.badssl.com/", bad, "null"),
  ("https://mozilla-old.badssl.com/", bad_broken, "mozilla-old"),
  ("https://mozilla-intermediate.badssl.com/", dubious_broken, "mozilla-intermediate"),
  ("https://mozilla-modern.badssl.com/", good, "mozilla-modern"),
  ("https://dh480.badssl.com/", bad, "dh480"),
  ("https://dh512.badssl.com/", bad, "dh512"),
  ("https://dh1024.badssl.com/", dubious_broken, "dh1024"),
  ("https://dh2048.badssl.com/", good, "dh2048"),
  ("https://dh-small-subgroup.badssl.com/", bad_broken, "dh-small-subgroup"),
  ("https://dh-composite.badssl.com/", bad_broken, "dh-composite"),
  ("https://static-rsa.badssl.com/", dubious_broken, "static-rsa"),
  ("https://tls-v1-0.badssl.com:1010/", dubious_broken, "tls-v1-0"),
  ("https://tls-v1-1.badssl.com:1011/", dubious_broken, "tls-v1-1"),
  ("https://invalid-expected-sct.badssl.com/", bad_broken, "invalid-expected-sct"),
  ("https://hsts.badssl.com/", good, "hsts"),
  ("https://upgrade.badssl.com/", good, "upgrade"),
  ("https://preloaded-hsts.badssl.com/", good, "preloaded-hsts"),
  ("https://subdomain.preloaded-hsts.badssl.com/", bad, "subdomain.preloaded-hsts"),
  ("https://https-everywhere.badssl.com/", good, "https-everywhere"),
  ("https://long-extended-subdomain-name-containing-many-letters-and-dashes.badssl.com/", good,
    "long-extended-subdomain-name-containing-many-letters-and-dashes"),
  ("https://longextendedsubdomainnamewithoutdashesinordertotestwordwrapping.badssl.com/", good,
    "longextendedsubdomainnamewithoutdashesinordertotestwordwrapping"),
  ("https://superfish.badssl.com/", bad, "(Lenovo) Superfish"),
  ("https://edellroot.badssl.com/", bad, "(Dell) eDellRoot"),
  ("https://dsdtestprovider.badssl.com/", bad, "(Dell) DSD Test Provider"),
  ("https://preact-cli.badssl.com/", bad, "preact-cli"),
  ("https://webpack-dev-server.badssl.com/", bad, "webpack-dev-server"),
  ("https://mitm-software.badssl.com/", bad, "mitm-software"),
  ("https://sha1-2016.badssl.com/", dubious, "sha1-2016"),
  ("https://sha1-2017.badssl.com/", bad, "sha1-2017"),
]


suite "SSL certificate check - httpclient":

  for i, ct in certificate_tests:

    test ct.desc:
      var client = newHttpClient()
      let exception_msg =
        try:
          let a = $client.getContent(ct.url)
          ""
        except:
          getCurrentExceptionMsg()

      let raised = (exception_msg.len > 0)
      let should_not_raise = ct.category in {good, dubious_broken, bad_broken}
      if should_not_raise xor raised:
        # we are seeing a known behavior
        if ct.category in {good_broken, dubious_broken, bad_broken}:
          skip()
        if raised:
          check exception_msg == "No SSL certificate found." or
            exception_msg == "SSL Certificate check failed." or
            exception_msg.contains("certificate verify failed") or
            exception_msg.contains("key too small") or
            exception_msg.contains "shutdown while in init"

      else:
        # this is unexpected
        if raised:
          echo "         $# ($#) raised: $#" % [ct.desc, $ct.category, exception_msg]
        else:
          echo "         $# ($#) did not raise" % [ct.desc, $ct.category]
        fail()



# threaded tests


type
  TTOutcome = ref object
    desc, exception_msg: string
    category: Category

proc run_t_test(ct: CertTest): TTOutcome {.thread.} =
  ## Run test in a {.thread.} - return by ref
  result = TTOutcome(desc:ct.desc, exception_msg:"", category: ct.category)
  try:
    var client = newHttpClient()
    let a = $client.getContent(ct.url)
  except:
    result.exception_msg = getCurrentExceptionMsg()


suite "SSL certificate check - httpclient - threaded":

  # Spawn threads before the "test" blocks
  var outcomes = newSeq[FlowVar[TTOutcome]](certificate_tests.len)
  for i, ct in certificate_tests:
    let t = spawn run_t_test(ct)
    outcomes[i] = t

  # create "test" blocks and handle thread outputs
  for t in outcomes:
    let outcome = ^t  # wait for a thread to terminate

    test outcome.desc:

      let raised = (outcome.exception_msg.len > 0)
      let should_not_raise = outcome.category in {good, dubious_broken, bad_broken}
      if should_not_raise xor raised:
        # we are seeing a known behavior
        if outcome.category in {good_broken, dubious_broken, bad_broken}:
          skip()
        if raised:
          check outcome.exception_msg == "No SSL certificate found." or
            outcome.exception_msg == "SSL Certificate check failed." or
            outcome.exception_msg.contains("certificate verify failed") or
            outcome.exception_msg.contains("key too small") or
            outcome.exception_msg.contains "shutdown while in init"

      else:
        # this is unexpected
        if raised:
          echo "         $# ($#) raised: $#" % [outcome.desc, $outcome.category, outcome.exception_msg]
        else:
          echo "         $# ($#) did not raise" % [outcome.desc, $outcome.category]
        fail()


# net tests


type NetSocketTest = tuple[hostname: string, port: Port, category:Category, desc: string]
const net_tests:array[0..4, NetSocketTest] = [
  ("imap.gmail.com", 993.Port, good, "IMAP"),
  ("wrong.host.badssl.com", 443.Port, bad, "wrong.host"),
  ("captive-portal.badssl.com", 443.Port, bad, "captive-portal"),
  ("expired.badssl.com", 443.Port, bad, "expired"),
  ("null.badssl.com", 443.Port, bad, "null"),
]


suite "SSL certificate check - sockets":

  for ct in net_tests:

    test ct.desc:

      var sock = newSocket()
      var ctx = newContext()
      ctx.wrapSocket(sock)
      let exception_msg =
        try:
          sock.connect(ct.hostname, ct.port)
          ""
        except:
          getCurrentExceptionMsg()

      let raised = (exception_msg.len > 0)
      let should_not_raise = ct.category in {good, dubious_broken, bad_broken}
      if should_not_raise xor raised:
        # we are seeing a known behavior
        if ct.category in {good_broken, dubious_broken, bad_broken}:
          skip()
        if raised:
          check exception_msg == "No SSL certificate found." or
            exception_msg == "SSL Certificate check failed." or
            exception_msg.contains "certificate verify failed"

      else:
        # this is unexpected
        if raised:
          echo "         $# ($#) raised: $#" % [ct.desc, $ct.category, exception_msg]
        else:
          echo "         $# ($#) did not raise" % [ct.desc, $ct.category]
        fail()
