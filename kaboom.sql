######### PURCHASE INTENTION BY MEANS OF RFM #########

# Calculate rfm variables
CREATE TABLE rfm
WITH temp AS (
	#calculate recency
	SELECT
		transaction_dimensions.customerid,
		DATEDIFF(MAX(transaction_dimensions.orderdatetime), MIN(transaction_dimensions.orderdatetime)) AS Recency
	FROM transaction_dimensions
	GROUP BY transaction_dimensions.customerid
)

SELECT 
	transaction_dimensions.customerid,
    transaction_id,
    temp.Recency,
    COUNT(*) AS Frequency,
    # Recalculate in EUR
    SUM(value*fx_rates_eur.rate) AS MonetaryValue,
    transaction_dimensions.channel_id
FROM transaction_dimensions
JOIN fx_rates_eur ON transaction_dimensions.currency = fx_rates_eur.ccy
JOIN temp ON transaction_dimensions.customerid = temp.customerid
GROUP BY customerid, transaction_dimensions.channel_id, transaction_dimensions.transaction_id
ORDER BY COUNT(*) DESC;

#view dimensions
SELECT
	transaction_dimensions.transaction_id,
    DATEDIFF(MAX(transaction_dimensions.orderdatetime), MIN(transaction_dimensions.orderdatetime)) AS Recency
FROM transaction_dimensions
GROUP BY transaction_id;

# View rfm
SELECT *
FROM rfm
ORDER BY Recency DESC;


######### COMBINE RFM TO FIND MOST COST EFFECTIVE CHANNEL PER SEGMENT #########

# Prepare channel data before grouping with segment
-- customerid | transaction_id | channel_id | transaccost | revenue | *segment*

CREATE TABLE channel_costs 
WITH temp1 AS (
	SELECT
		transaction_financials.transaction_id,
		SUM(marketing_cost*fx_rates_eur.rate) AS marketing_cost_eur,
        SUM(operation_cost*fx_rates_eur.rate) AS operation_cost_eur,
        SUM(administration_cost*fx_rates_eur.rate) AS administration_cost_eur,
        SUM(commission_revenue*fx_rates_eur.rate) AS commission_revenue_eur,
        SUM(other_revenue*fx_rates_eur.rate) AS other_revenue_eur
	FROM transaction_financials
	JOIN fx_rates_eur
    ON transaction_financials.currency = fx_rates_eur.ccy
	GROUP BY transaction_financials.transaction_id
	)
SELECT
	rfm.customerid,
    rfm.transaction_id,
    rfm.channel_id,
    SUM(temp1.marketing_cost_eur+operation_cost_eur) AS cost_eur,
    SUM(temp1.administration_cost_eur+temp1.commission_revenue_eur+temp1.other_revenue_eur) AS revenue_eur
FROM rfm
JOIN temp1 ON rfm.transaction_id = temp1.transaction_id
GROUP BY customerid, transaction_id, channel_id;

# View channel_cost
SELECT *
FROM channel_costs;

# Merge channel_cost with segment
CREATE TABLE channel_segment
SELECT 
	channel_costs.customerid,
    channel_costs.transaction_id,
    channel_costs.channel_id,
    channel_costs.cost_eur,
    channel_costs.revenue_eur,
    segments.Segment
FROM channel_costs
JOIN segments
ON channel_costs.customerid = segments.customerid;

# View channel_segment
SELECT *
FROM channel_segment;

######### COMPANY HEALTH #########

# Have a look at the transaction financials dataset
SELECT *
FROM transaction_financials
LIMIT 10;

# Have a look at the transaction dimensions dataset
SELECT *
FROM transaction_dimensions
WHERE customercityid = '020173e9e0c9728683fc9bfa7cef1a8cdae2ea14'
LIMIT 10;

# Have a look at the transaction dimensions dataset
SELECT *
FROM cities
WHERE city_id = '020173e9e0c9728683fc9bfa7cef1a8cdae2ea14'
LIMIT 10;

# Recalculate cost and revenue
SELECT 
	SUM((transaction_financials.marketing_cost + transaction_financials.operation_cost + transaction_financials.administration_cost))*AVG(fx_rates_eur.rate) AS cost_eur, 
	SUM((commission_revenue + other_revenue))*AVG(fx_rates_eur.rate) AS revenue_eur,
    SUM((commission_revenue + other_revenue))*AVG(fx_rates_eur.rate)-SUM((transaction_financials.marketing_cost + transaction_financials.operation_cost + transaction_financials.administration_cost))*AVG(fx_rates_eur.rate) AS profit
FROM transaction_financials
JOIN fx_rates_eur ON transaction_financials.currency = fx_rates_eur.ccy;

# Get data per day with country + city and recalculated to EUR currency - grouped
CREATE TABLE transactions
SELECT 
	# Add date from dimensions table
    CAST(transaction_dimensions.orderdatetime AS date) AS date,
    # Add country
    transaction_dimensions.country,
    transaction_dimensions.customercityid,
    # Recalculate all cost + revenue to EUR
    SUM(transaction_financials.marketing_cost)*AVG(fx_rates_eur.rate) AS marketing_cost_eur,
	SUM(transaction_financials.operation_cost)*AVG(fx_rates_eur.rate) AS operation_cost_eur,
	SUM(transaction_financials.administration_cost)*AVG(fx_rates_eur.rate) AS administration_cost_eur,
	SUM(transaction_financials.commission_revenue)*AVG(fx_rates_eur.rate) AS commission_revenue_eur,
	SUM(transaction_financials.other_revenue)*AVG(fx_rates_eur.rate) AS other_revenue_eur,
	SUM((transaction_financials.marketing_cost + transaction_financials.operation_cost + transaction_financials.administration_cost))*AVG(fx_rates_eur.rate) AS cost_eur, 
	SUM((commission_revenue + other_revenue))*AVG(fx_rates_eur.rate) AS revenue_eur,
    SUM((commission_revenue + other_revenue))*AVG(fx_rates_eur.rate)-SUM((transaction_financials.marketing_cost + transaction_financials.operation_cost + transaction_financials.administration_cost))*AVG(fx_rates_eur.rate) AS profit,
    COUNT(*) AS orders,
    (COUNT(*) / LAG(COUNT(*)) OVER (ORDER BY CAST(transaction_dimensions.orderdatetime AS date)) - 1) as order_growth
FROM transaction_financials
JOIN transaction_dimensions
ON transaction_financials.transaction_id = transaction_dimensions.transaction_id
JOIN fx_rates_eur ON transaction_financials.currency = fx_rates_eur.ccy
GROUP BY CAST(transaction_dimensions.orderdatetime AS date), transaction_dimensions.country, transaction_dimensions.customercityid
ORDER BY date ASC;
