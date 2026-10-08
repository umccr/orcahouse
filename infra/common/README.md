# Legacy Common

> DEPRECATED. 
> 
> Wrong Way. Please U Turn.

Unlike application software coding (which is a norm pattern to promote DRY), it is strategically better for IaC (Infrastructure as Code) to be WET.

We do not want to take down the production environment by a mistake (e.g. wrong assumption, technology drift) made between a piece of shared infrastructure code.

Especially when the shared module code is crossing over different stacks, whereas each stack has its own concerns. We have to keep them separate for maintainability.

Please adapt to the pattern whereas **the shared terraform module be bounded within a stack**.

## Single Stack – Shared Module – Multiple Environments

* [lakeformation](../lakeformation)
* [redshift](../redshift)

## Multiple Stacks – Share Nothing – Use Case Specific

* [s3](../s3)
* [vpc](../vpc)
* [ec2](../ec2)

## Mix-Match

You may leverage both code structures within the same "**AWS service category**" e.g. `AWS Glue Crawler` service.

* [glue-crawler](../glue-crawler)
