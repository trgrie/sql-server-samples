# SQL Server Samples Repository
This GitHub repository contains code samples that demonstrate how to use Microsoft's SQL products including SQL Server, Azure SQL Database, and Azure SQL Data Warehouse. Each sample includes a README file that explains how to run and use the sample.

Note that certain features like In-Memory OLTP are edition specific for SQL Server and would be possible to implement if the edition which supports that feature is being used to run the sample. 

## Releases in this repository

Releases allow you to conveniently download sample databases or applications without the need to build them from source code. This SQL Server samples repository has the following notable releases:

  - [Wide World Importers sample database v1.0](https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0) is the main sample for SQL Server 2016 and Azure SQL Database. It contains both an OLTP and an OLAP database.
  - [In-Memory OLTP Performance Demo v1.0](https://github.com/Microsoft/sql-server-samples/releases/tag/in-memory-oltp-demo-v1.0) illustrates the performance benefits of the In-Memory OLTP technology built into SQL Server and Azure SQL Database.
  - [IoT Smart Grid sample v1.0](https://github.com/Microsoft/sql-server-samples/releases/tag/iot-smart-grid-v1.0) illustrates how SQL Server can be leveraged to ingest data from IoT devices and sensors, and how you can run analytics on that data.

To see the complete list of resources in this repository, navigate to [Releases](https://github.com/Microsoft/sql-server-samples/releases)

## Working in GitHub
To work in GitHub, go to https://github.com/microsoft/sql-server-samples and fork the repository. Work in your own fork and when you are ready to submit to make a change or publish your sample for the first time, submit a pull request into the master branch of sql-server-samples. One of the approvers will review your request and accept or reject the pull request.

Each sample should be in its own folder with a README.md file that follows the [template](README_samples_template.md). Generated files (e.g., .exe or .bacpac) and user configuration settings (e.g., .user) should not be committed to GitHub.

## Code of Conduct
This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## License
These samples and templates are all licensed under the MIT license. See the license.txt file in the root.

## Questions
Email questions to: sqlserversamples@microsoft.com.
