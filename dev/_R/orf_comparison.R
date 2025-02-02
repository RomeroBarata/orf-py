################################################################################
###         R vs. Python Comparison of the Ordered Forest Estimation         ###
################################################################################

# set the directory to the one of the source file (requires Rstudio)
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
path <- getwd()

# load packages
library(ggplot2)
library(tidyverse)
library(stevedata)
library(orf)

# ---------------------------------------------------------------------------- #

# Empirical Data
# load data on health outcome from stevedata package
data("mm_nhis", package = "stevedata")
dataset <- mm_nhis
# subset the data only with the desired varlist as in mastering metrics example
varlist <- c("hi", "hlth", "nwhite", "age", "yedu", "famsize", "empl", "inc", "fml")
dataset <- dataset[, varlist]
# outcome
dataset$y <- dataset$hlth
# remove original variable
dataset$hlth <- NULL
# remove NAs
dataset <- dataset[complete.cases(dataset), ]
dataset <- as.data.frame(dataset)
# rename vars nicely
colnames(dataset) <- c("HealthInsurance", "NonWhite", "Age", "Education",
                       "FamilySize", "Employed", "Income", "Female", "y")
# save data to disk
write.csv(dataset, file = paste0(path, '/data/empdata_test.csv'), row.names = F)

# ---------------------------------------------------------------------------- #

# Synthetic Data
# generate example data using the DGP from orf package data
set.seed(123) # set seed for replicability

# number of observations (at least 10k for reliable comparison)
n  <- 10000

# various covariates
X1 <- rnorm(n, 0, 1)    # continuous
X2 <- rbinom(n, 2, 0.5) # categorical
X3 <- rbinom(n, 1, 0.5) # dummy
X4 <- rnorm(n, 0, 10)   # noise

# bind into matrix
X <- as.matrix(cbind(X1, X2, X3, X4))
# deterministic component
deterministic <- X1 + X2 + X3
# generate continuous outcome with logistic error
Y <- deterministic + rlogis(n, 0, 1)
# thresholds for continuous outcome
cuts <- quantile(Y, c(0, 1/3, 2/3, 1))
# discretize outcome into ordered classes 1, 2, 3
Y <- as.numeric(cut(Y, breaks = cuts, include.lowest = TRUE))

# save data as a dataframe
odata_synth <- as.data.frame(cbind(Y, X))
# save data to disk
write.csv(odata_synth, file = paste0(path, '/data/odata_test.csv'), row.names = F)

# ---------------------------------------------------------------------------- #

# Synthetic Data directly from orf R package
data(odata)
# save data to disk
write.csv(odata, file = paste0(path, '/data/odata_package.csv'), row.names = F)

# ---------------------------------------------------------------------------- #

# Synthetic Data directly from orf PyPi package
odata_pip <- as.data.frame(read_csv(file = paste0(path, '/data/odata_pip.csv')))

# ---------------------------------------------------------------------------- #

# Benchmark settings:
replace_options <- list(FALSE, TRUE)
honesty_options <- list(FALSE, TRUE)
inference_options <- list(FALSE, TRUE)
data_types <- list('synth', 'emp', 'pip', 'package')

# start benchmarks
for (data_idx in data_types) {
  # based on data type, determine X and Y
  if (data_idx == 'synth') {
    # specify response and covariates
    Y <- as.numeric(odata_synth[, 1])
    X <- as.matrix(odata_synth[, -1])
  } else if (data_idx == 'emp') {
    # specify response and covariates
    X <- as.matrix(dataset[, 1:ncol(dataset)-1])
    Y <- as.numeric(dataset[, ncol(dataset)])
  } else if (data_idx == 'pip') {
    # specify response and covariates
    Y <- as.numeric(odata_pip[, 1])
    X <- as.matrix(odata_pip[, -1])
  } else {
    # specify response and covariates
    Y <- as.numeric(odata[, 1])
    X <- as.matrix(odata[, -1])
  }
  
  # loop through different settings and save the results
  for (inference_idx in inference_options) {
    # loop through honesty options
    for (honesty_idx in honesty_options) {
      # check if the setting is admissible
      if (inference_idx == TRUE & honesty_idx == FALSE) {
        next
      }
      # lastly loop through subsampling option
      for (replace_idx in replace_options) {
        # check if the setting is admissible (for comparison with python)
        if (honesty_idx == TRUE & replace_idx == TRUE) {
          next
        }
        # print current iteration
        print(paste('data:', data_idx,
                    'inference:', inference_idx,
                    'honesty:',honesty_idx,
                    'replace:', replace_idx, sep = " "))
        # set seed for replicability
        set.seed(123)
        # fit orf (at least 2000 trees for reliable comparison)
        orf_fit <- orf(X, Y, num.trees = 2000, min.node.size = 5, mtry = 0.3,
                       replace = replace_idx,
                       honesty = honesty_idx,
                       inference = inference_idx)
        
        # get in-sample results
        orf_pred <- orf_fit$predictions
        orf_var <- orf_fit$variances
        orf_rps <- orf_fit$accuracy$RPS
        orf_mse <- orf_fit$accuracy$MSE
        # wrap into list
        fit_results <- list(orf_pred, orf_var, orf_rps, orf_mse)
        names(fit_results) <- c('orf_pred', 'orf_var', 'orf_rps', 'orf_mse')
        
        # get the plot
        orf_plot <- plot(orf_fit)
        
        # get the results for margins (mean margins for reliable comparison)
        orf_margins <- margins(orf_fit, eval = 'mean')
        margins_effects <- orf_margins$effects
        margins_vars <- orf_margins$variances
        # wrap into list
        margins_results <- list(margins_effects, margins_vars)
        names(margins_results) <- c('margins_effects', 'margins_vars')
        
        # save the results for plot
        ggsave(filename = paste0('/results/R_', data_idx, '_', 'plot_I_', inference_idx, 
                                 '_H_', honesty_idx, '_R_', replace_idx, '.png'),
               plot = orf_plot, path = path)
        
        # save the results for fit
        for (fit_idx in seq_along(fit_results)) {
          # check if its empty
          if (is.null(fit_results[[fit_idx]])) {
            next
          }
          # save the results
          write.csv(fit_results[[fit_idx]],
                    file = paste0(path, '/results/R_', data_idx, '_',
                                  names(fit_results)[[fit_idx]],
                                  '_I_', inference_idx, '_H_', honesty_idx, '_R_',
                                  replace_idx, '.csv'),
                    row.names = FALSE)
        }
        
        # save the results for margins
        for (margin_idx in seq_along(margins_results)) {
          # check if its empty
          if (is.null(margins_results[[margin_idx]])) {
            next
          }
          # save the results
          write.csv(margins_results[[margin_idx]],
                    file = paste0(path, '/results/R_', data_idx, '_',
                                  names(margins_results)[[margin_idx]],
                                  '_I_', inference_idx, '_H_', honesty_idx, '_R_',
                                  replace_idx, '.csv'),
                    row.names = FALSE)
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------- #