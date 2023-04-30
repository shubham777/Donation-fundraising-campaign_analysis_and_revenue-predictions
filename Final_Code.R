# Load the package
library(RODBC)

db = odbcConnect("mysql_server_64", uid="root", pwd="test123")
sqlQuery(db, "USE ma_charity")

#removing error entries
query = "DELETE FROM assignment2 WHERE contact_id IN (4259133, 4101923,
4161982, 1565912, 1686812, 1781786, 2040061, 663127, 2348680,
686511, 795666, 2288596)"

sqlQuery(db, query)

# Extract calibration data from database
query = "SELECT c.contact_id,
DATEDIFF(20220531, MAX(a.act_date)) / 365 AS 'recency',
DATEDIFF(20220531, MIN(a.act_date)) / 365 AS 'firstdonation',
COUNT(a.amount) AS 'frequency',
AVG(a.amount) AS 'avgamount',
MAX(a.amount) AS 'maxamount',
MIN(a.amount) AS 'minamount',
SUM(a.amount) AS 'totalamount' ,
IF(c.donation = 1, 1, 0) AS 'loyal',
c.amount AS 'targetamount'
FROM acts a
RIGHT JOIN (SELECT *
FROM assignment2
WHERE (calibration = 1)) AS c
ON c.contact_id = a.contact_id
GROUP BY 1"


data = sqlQuery(db, query)
print(nrow(data))
# probability model
library(nnet)
prob.model = multinom(formula = loyal ~ (recency*frequency)  + log(recency) + log(firstdonation) + log(frequency),
                      data = data)

print(summary(prob.model))
#donation amount model
z = which(!is.na(data$targetamount))
amount.model = lm(formula = log(targetamount) ~  frequency + log(avgamount) +  log(maxamount) +log(totalamount)/frequency,
                  data = data[z, ])

print(summary(amount.model))



#cross fold validation
formula = loyal ~ (recency*frequency) +log(recency) + log(firstdonation) + log(frequency)
nfold = 5
nobs  = nrow(data)
index = rep(1:nfold, length.out = nobs)
probs = rep(0, nobs)
accuracy = 0
for (i in 1:nfold) {
  
  # Assign in-sample and out-of-sample observations
  insample  = which(index != i)
  outsample = which(index == i)
  
  # Run model on in-sample data only
  submodel = multinom(formula , data[insample, ])
  
  # Obtain predicted probabilities on out-of-sample data
  probs[outsample] = predict(object = submodel, newdata = data[outsample, ], type = "probs")
  
  
  out = data.frame(contact_id = data[outsample, ]$contact_id)
  out$truth = data[outsample, ]$loyal
  out$probs  = predict(object = submodel, newdata = data[outsample, ], type = "probs")
  out$amount = exp(predict(object = amount.model, newdata = data[outsample, ]))
  out$score  = out$probs * out$amount
  out$solicit = with(out, ifelse(score>2, 1, 0))
  out$solicit[which(is.na(out$solicit))] = 0
  
  #model evaluation
  cm = confusionMatrix(table(out$solicit,out$truth),
                       positive="1",mode="prec_recall")
  if(cm$overall[1]>accuracy){
    accuracy = cm$overall[1]
    print(accuracy)
    prob.model = submodel
  }
}

# Extract prediction data from database
query = "SELECT C.contact_id,
DATEDIFF(20220531, MAX(a.act_date)) / 365 AS 'recency',
DATEDIFF(20220531, MIN(a.act_date)) / 365 AS 'firstdonation',
COUNT(a.amount) AS 'frequency',
AVG(a.amount) AS 'avgamount',
MAX(a.amount) AS 'maxamount',
MIN(a.amount) AS 'minamount',
SUM(a.amount) AS 'totalamount' 
FROM acts a
RIGHT JOIN (SELECT contact_id, calibration
FROM assignment2
WHERE (calibration = 0)
GROUP BY contact_id) AS c
ON c.contact_id = a.contact_id
GROUP BY 1" 

newdata = sqlQuery(db, query)
print(nrow(newdata))
# Close the connection
odbcClose(db)

# predictions
out = data.frame(contact_id = newdata$contact_id)
out$probs  = predict(object = prob.model, newdata = newdata, type = "probs")
out$amount = exp(predict(object = amount.model, newdata = newdata))
out$score  = out$probs * out$amount
out$solicit = with(out, ifelse(score>2, 1, 0))
out$solicit[which(is.na(out$solicit))] = 0

#create data-frame in descibed format
final_solution =  data.frame(contact_id = out$contact_id)
final_solution$solicit = out$solicit

#no. of solicit
x = which(final_solution$solicit==1)
print(length(x))

#write in txt file
write.table(final_solution, file = "assignment2.txt", sep = "\t" , row.names = FALSE , col.names = FALSE)
