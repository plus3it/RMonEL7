# How to contribute

This project originated to make automation of RedMine sites for internal processes easier. The objective of this "ease" being to allow site-deployments to be handed over to a staff more versed on _running_ a RedMine site and less versed on the AWS-based "plumbing" under that RedMine site.

The fruits of this automation-effort are openly provided on an "as-is". Individuals who have stumbled on this project and find deficiencies in it are invited to help us enhance the project for broader usability. This can be done by opening issues against the project or, even better, offering enhancements via Pull Requests.

## Testing

This project leverages a fairly bare-bones test-suite performed through Travis CI's [online testing framework](https://travis-ci.org/). As of this contribution-guideline document's last edit date, the only things being tested for are JSON sytax de-linting for the CFn templates and shell (BASH) style and syntax checking via the shellchecker utility. JSON de-linting is done via a simple, `jq`-based test. Shell style- and syntax-checking are done via [Koalaman's shellcheck utilities](https://github.com/koalaman/shellcheck) (functionality which is also available via copy/paste at https://www.shellcheck.net/). The current test "recipies"are found in the `.travis.yml` file found in the project's root directory.

## Submitting Changes

Please send a GitHub Pull Request with a clear list of what changes are being offered (read more about [pull requests](http://help.github.com/pull-requests/)). If the received PR doesn't show green in Travis, it will be rejected. It is, therefore, recommended that prior to submitting a pull request, Travis will have been leveraged to pre-validate changes in the fork.

Feel free to enhance the Travis-based checks as desired. Modifications to the `.travis.yml` received via a PR will be evaluated for inclusion as necessary. If other testing frameworks are preferred, please feel free to add them via a PR ...ensuring that the overall PR still passes the existing Travis CI framework. Any way you slice it, improvements in testing are great. We would be very glad of receiving and evaluating any testing-enhancements provided.

Please ensure that commits are performed with both clear and concise commit messages. One-line messages are fine for small changes, but bigger changes should look like this:

    $ git commit -m "A brief summary of the commit
    > 
    > A paragraph describing what changed and its impact."

## Coding conventions

Start by reading the existing code. Things are fairly straight-forward.  We optimize for narrower terminal widths - typically 80-characters but sometimes 120-characters. We also optimize for UNIX-style end-of-line. Please ensure that your contributions line-ends use just a line-feed rather (lf) than a carriage-return/line-feed (crlf). Note that the project-provided `.editorconfig` file should help ensure this behavior.
* JSON is generally run through a python-filter (`python -m json.tool`) prior to committing. The default-spacing on python-filter uses four-space indent-increments. As a result of our preferred character-width limits, our indent-increments are reduced to two spaces. Please follow this convention.
* Shell script conventions are fairly minimal
    * Pass the shellchecker validity tests
    * Use three-space indent-increments for basic indenting
    * If breaking across lines, indent following lines by two-spaces (to better differentiate from standard indent-blocks) - obviously, this can be ignored for here-documents.
    * Code should be liberally-commented.
       * Use "# " or "## " to prepend.
       * Indent comment-lines/blocks to line up with the blocks of code being commented
    * Anything not other specified - either explicitly as above or implicitly via pre-existing code -  pick an element-style and be consistent with it 


## Additonal Notes

* The EC2 components have generally been designed to work within STIGed environments:
    * The EC2 components have only been actively been tested against the spel/AMIgen7 AMI family (search `spel-minimal-centos-7` or `spel-minimal-rhel-7` from the community AMIs). Other AMIs will likely work but have not been actively tested against.
    * The EC2 CFn templates attempt to STIG-harden the AMI by using the watchmaker haredning utility.
        * The Watchmaker tools use [SaltStack](https://saltstack.com/salt-open-source/) to apply STIG hardening to the EC2 node.
        * See [ReadTheDocs.IO](https://watchmaker.readthedocs.io/) for more-detailed information about Watchmaker's use.
        * See the [GitHub Project](https://github.com/plus3it/watchmaker.git) to review the actual Watchmaker code.
* Spawned elements names (S3 bucket names, RDS FQDNs, etc.) are generally left up to AWS's automated naming-capabilities to name. These names are ugly but have a significantly lower likelihood of colliding with other AWS objects. Some of the templates allow specification, but such specification is generally not recommended.
