# Third-party notices

Busclear is licensed under the GNU General Public License v3.0 (see
[LICENSE](../LICENSE)). Dependencies from pub.dev keep their own licences; the
apps list them under "Licences". This file covers code and data that live in
this repository but come from elsewhere.

## xknx

KNX Secure in this repository (`packages/knx/lib/src/secure/knx_crypto.dart`
and `data_secure.dart`, used by the app and the add-on server) follows the
structure of [xknx](https://github.com/XKNX/xknx) and is checked against its
examples. The test keyrings in `test/resources/` (`SecureTest.knxkeys`,
`testcase.knxkeys`) and the keys and frames in
`packages/knx/test/data_secure_test.dart` are taken from the xknx tests. The
package carries the same notice in `packages/knx/NOTICE`. xknx is licensed
under the MIT License:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.

## local_auth_windows

`third_party/local_auth_windows/` is a modified copy of the Flutter plugin
`local_auth_windows`, under its own licence in
[third_party/local_auth_windows/LICENSE](../third_party/local_auth_windows/LICENSE).
Why it is vendored and when it goes away: `README.vendored.md` in the same
folder.

## Horizont

The design system [Horizont](https://github.com/regetskcob/horizont) is MIT
licensed. Its fonts keep their own licences (SIL Open Font License 1.1,
Apache 2.0), see its [LICENSING.md](https://github.com/regetskcob/horizont/blob/main/LICENSING.md).
