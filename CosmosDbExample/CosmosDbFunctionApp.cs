using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace CosmosDbExample
{
    public class CosmosDBEntity
    {
        [JsonProperty(PropertyName = "id")]
        public string Id { get; set; }

        [JsonProperty(PropertyName = "name")]
        public string Name { get; set; }

        [JsonProperty(PropertyName = "createdAt")]
        public DateTime? CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class CosmosDbFunctionApp
    {
        private const string DatabaseName = "entities_db";
        private const string ContainerName = "entities";
        private const string Connection = "cosmosDBConnection";
        private readonly ILogger _logger;

        public CosmosDbFunctionApp(ILogger<CosmosDbFunctionApp> logger)
        {
            _logger = logger;
        }

        [FunctionName("CosmosDBTrigger")]
        public void Run([CosmosDBTrigger(
            databaseName: DatabaseName,
            containerName: ContainerName,
            Connection = Connection,
            LeaseContainerName = "leases",
            CreateLeaseContainerIfNotExists = false)]IReadOnlyList<CosmosDBEntity> input)
        {
            _logger.LogInformation("Event from change feed...");
            if (input != null && input.Count > 0)
            {
                _logger.LogInformation("Documents modified " + input.Count);
                _logger.LogInformation("First document Id " + input[0].Id);
            }
        }

        [FunctionName("HttpInsertItem")]

        public async Task<IActionResult> InsertAsync(
            [HttpTrigger( Microsoft.Azure.WebJobs.Extensions.Http.AuthorizationLevel.Anonymous,"POST", Route = "api/entities" )] HttpRequest req,
            [CosmosDB(
                databaseName: DatabaseName,
                containerName: ContainerName,
                Connection = Connection)]IAsyncCollector<CosmosDBEntity> entities)
        {
            var reader = new System.IO.StreamReader(req.Body);
            var entity = JsonConvert.DeserializeObject<CosmosDBEntity>(await reader.ReadToEndAsync());
            await entities.AddAsync(entity);
            return new OkObjectResult(entity);
        }

        [FunctionName("HttpGetItem")]
        public IActionResult GetAsync(
                       [HttpTrigger( Microsoft.Azure.WebJobs.Extensions.Http.AuthorizationLevel.Anonymous,"GET", Route = "api/entities/{id}" )] HttpRequest req,
                    [CosmosDB(
                           databaseName: DatabaseName,
                           containerName:ContainerName,
                           Connection = Connection,
                            PartitionKey = "{id}",
                           Id = "{id}")]CosmosDBEntity entity)
        {
            if(entity == null)
            {
                return new NotFoundResult();
            }
            return new OkObjectResult(entity);
        }
    }
}
