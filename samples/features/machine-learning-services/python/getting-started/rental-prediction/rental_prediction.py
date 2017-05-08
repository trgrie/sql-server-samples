import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error

from revoscalepy.computecontext.RxInSqlServer import RxInSqlServer
from revoscalepy.computecontext.RxInSqlServer import RxSqlServerData
from revoscalepy.etl.RxImport import rx_import_datasource


def get_rental_predictions():
    conn_str = 'Driver=SQL Server;Server=MYSQLSERVER;Database=TutorialDB;Trusted_Connection=True;'
    column_info = { 
            "Year" : { "type" : "integer" },
            "Month" : { "type" : "integer" }, 
            "Day" : { "type" : "integer" }, 
            "RentalCount" : { "type" : "integer" }, 
            "WeekDay" : { 
                "type" : "factor", 
                "levels" : ["1", "2", "3", "4", "5", "6", "7"]
            },
            "Holiday" : { 
                "type" : "factor", 
                "levels" : ["1", "0"]
            },
            "Snow" : { 
                "type" : "factor", 
                "levels" : ["1", "0"]
            }
        }

    data_source = RxSqlServerData(table="dbo.rental_data",
                                  connectionString=conn_str, colInfo=column_info)
    computeContext = RxInSqlServer(
        connectionString = conn_str,
        numTasks = 1,
        autoCleanup = False
        )
     
    
    RxInSqlServer(connectionString=conn_str, numTasks=1, autoCleanup=False)
    
    # import data source and convert to pandas dataframe
    df = pd.DataFrame(rx_import_datasource(data_source))
    print("Data frame:", df)
    # Get all the columns from the dataframe.
    columns = df.columns.tolist()
    # Filter the columns to remove ones we don't want.
    columns = [c for c in columns if c not in ["Year"]]
    # Store the variable we'll be predicting on.
    target = "RentalCount"
    # Generate the training set.  Set random_state to be able to replicate results.
    train = df.sample(frac=0.8, random_state=1)
    # Select anything not in the training set and put it in the testing set.
    test = df.loc[~df.index.isin(train.index)]
    # Print the shapes of both sets.
    print("Training set shape:", train.shape)
    print("Testing set shape:", test.shape)
    # Initialize the model class.
    lin_model = LinearRegression()
    # Fit the model to the training data.
    lin_model.fit(train[columns], train[target])
    # Generate our predictions for the test set.
    lin_predictions = lin_model.predict(test[columns])
    print("Predictions:", lin_predictions)
    # Compute error between our test predictions and the actual values.
    lin_mse = mean_squared_error(lin_predictions, test[target])
    print("Computed error:", lin_mse)

get_rental_predictions()
