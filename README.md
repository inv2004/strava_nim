### Automatic training diary from strava

The draft version is able to:
- [x] Starts http server to redirect into google and strava auth's
- [x] Request google email and spreadsheet access
- [x] Stores tokens locally
- [ ] Refresh token after expiration
- [x] Requests strava activities access
- [x] Find current date plan from spreadsheet
- [x] Download watts stream from strava
- [x] Find best intervals for the mentioned plan
        * needs improvement
- [ ] Store result into spreadsheet

### Build
```shell
nimble -d:ssl build
```

