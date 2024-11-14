## set-up ================================================================

## loading required packages
pacman::p_load(dplyr, stringr, tidyr, openai, worlddataverse)

## suppressing warnings
options(warn = -1)

## loading configurations and coicop tree
source("labels.R")
source("config.R")

## parsing command-line arguments
args <- commandArgs(trailingOnly = TRUE)

## error message for missing arguments
err_missing_args <- paste0("Missing parameters provided. This function requires three arguments. \n",
                           "\tfirst argument should be a string specifying the path to the products CSV\n",
                           "\tsecond argument should be a string with the name of the product id column\n",
                           "\tthird argument should be a string with the name of the product name column\n",
                           "try:\n",
                           "\tRscript coicop_labeller.R sample.csv index product_name_en")

## validate arguments ===================================================  

if (length(args) < 3) {
  cat(err_missing_args)
  quit()
} else if (length(args) == 3) {
  product_path <- args[1]
  product_id_col_name <- args[2]
  product_col_name <- args[3]
} else if (length(args) == 4) {
  product_path <- args[1]
  product_id_col_name <- args[2]
  product_col_name <- args[3]
  gpt_output_file <- args[4]
} else {
  cat(err_missing_args)
  quit()
}

## validate the arguments
if (is.na(product_path) || is.na(product_col_name) || is.na(product_id_col_name)) {
  cat(err_missing_args)
  quit()
}

## validate the product path
if (!grepl("\\.csv$", product_path)) {
  cat("The products file provided is not a .csv")
  quit()
}

## validate the product file
if (!file.exists(product_path)) {
  cat(paste("The file at", product_path, "does not exist."))
  quit()
}

## reading in the CSV
products <- read.csv(product_path)
missing_columns <- setdiff(c(product_id_col_name, product_col_name), colnames(products))

## validate the columns are present
if (length(missing_columns) > 0) {
  cat(paste("The following columns are missing from the products CSV:", paste(missing_columns, collapse = ", ")))
  quit()
}

## creating intermediary file to keep non-related columns from input data
intermediary_otherCols <- products  
intermediary_file_path <- "intermediary_otherCols.csv"
write.csv(intermediary_otherCols, intermediary_file_path, row.names = FALSE)

## setting default output file name if not provided
if (is.na(gpt_output_file) || gpt_output_file == "") {
  position <- regexpr("\\.csv$", product_path)
  gpt_output_file <- paste0(substr(product_path, 1, position - 1), "_output.csv")
  if (verbose) {
    print(paste("Missing GPT Output File. Setting GPT Output File name to", gpt_output_file))
  }
}

## setting up OpenAI API key
Sys.setenv(OPENAI_API_KEY = OPEN_API_KEY)

## Labeller function ================================================================

# This function takes in a csv of products that contains the following columns:
#   product_id_col_name: unique per row, this can simply be the index
#   product_col_name: the name of the product attempting to be classified

coicop_labeller <- function(products,
                            product_id_col_name,
                            product_col_name
) {

  ## function to create a unique file name for each chunk
  get_file_name <- function(chunk_index) {
    return(paste("gen_labels_", MODEL_SET, "_", chunk_index, sep = ""))
  }

  ## function to send a chunk of products to the OpenAI API for labeling
  generate_labels <- function(chunk_index, products_list) {

    # setting prompt and output file name
    prompt <- paste("Return the coicop codes for the items below in a csv format with the product_id and the coicop label such as: \n product_id, coicop label. ",
                    "Classify all ", CHUNK_SIZE, " of the labels provided below.",
                    chunk_to_str(products_list[[chunk_index]]), sep = "")
    out_file_name <- paste(local_path, get_file_name(chunk_index), ".txt", sep = "")

    # sending request to OpenAI API
    response <- create_chat_completion(
      model = OPEN_AI_MODEL,
      temperature = .5,
      n = 1,
      messages = list(
        list("role" = "system",
             "content" = systeminput),
        list("role" = "user",
             "content" = prompt)
      )
    )

    # writing the response to a file
    writeLines(response$choices$message.content, out_file_name)

    # calculating the cost of the request
    cost <- as.numeric(response$usage$prompt_tokens) * 0.005 / 1000 +
      as.numeric(response$usage$completion_tokens) * 0.0025 / 1000

    # printing the cost and tokens used
    if (verbose) {
      print(paste("Full Tokens used: ", 
                  response$usage$total_tokens,
                  " Approximate Cost: $",
                  round(cost, digits = 2), sep = ""))
    }
  }

  ## function to convert COICOP label columns to numeric
  predictions_to_numeric <- function(db) {
    db$coicop_modeled_1 <- as.numeric(db$coicop_modeled_1)
    db$coicop_modeled_2 <- as.numeric(db$coicop_modeled_2)
    db$coicop_modeled_3 <- as.numeric(db$coicop_modeled_3)
    return(db)
  }

  ## function to process labeled output and save it in CSV format
  gen_labels_to_csv <- function(chunk_index) {

    # reading the output file
    out_file_name <- paste(local_path, get_file_name(chunk_index), ".txt", sep = "")

    # reading the output file and extracting the CSV lines
    lines <- readLines(out_file_name)
    csv_line <- grep("csv", lines)
    lines <- lines[(csv_line + 1):length(lines)]
    temp_file <- tempfile()
    writeLines(lines, temp_file)

    # ensuring COICOP labels are in the correct format
    txt <- read.csv(temp_file, header = TRUE, stringsAsFactors = FALSE)
    txt[] <- lapply(txt, function(x) if (is.character(x)) trimws(x) else x)
    colnames(txt) <- c(product_id_col_name, "coicop.label")
    code_pattern <- "^\\d{1,2}\\.\\d{1}\\.\\d{1}\\.\\d{1}$"

    # filtering out the COICOP labels (so that any non-COICOP labels / content are removed)
    labelled_by_index <- txt %>%
      filter(str_detect(coicop.label, code_pattern) |
          str_detect(coicop.label, "^\\d{1,2}\\.\\d{1}\\.\\d{1}$") |
          str_detect(coicop.label, "^\\d{1,2}\\.\\d{1}$") |
          str_detect(coicop.label, "^\\d{1,2}$")
      ) %>%
      rename(code = coicop.label)

    # standardising the COICOP labels
    labelled_by_index <- labelled_by_index %>%
      mutate(code = case_when(
        str_detect(code, "^\\d{1,2}\\.\\d{1}\\.\\d{1}$") ~ paste0(code, ".0"),
        str_detect(code, "^\\d{1,2}\\.\\d{1}$") ~ paste0(code, ".0.0"),
        str_detect(code, "^\\d{1,2}$") ~ paste0(code, ".0.0.0"),
        TRUE ~ code
      ))

    # separating the COICOP labels into individual columns
    labelled_by_index <- separate(labelled_by_index, code, into = c("coicop_modeled_1", "coicop_modeled_2",
                                                                    "coicop_modeled_3"),
                                  sep = "\\.", fill = "right", convert = TRUE)
    
    # converting the COICOP labels to numeric
    labelled_by_index <- predictions_to_numeric(labelled_by_index)

    # add the product name
    labelled_by_index <- labelled_by_index %>%
      merge(select(products, c(product_col_name, product_id_col_name)), by = product_id_col_name, all.x = TRUE)

    # writing the labelled data to a CSV file
    write.csv(labelled_by_index, paste(local_path, get_file_name(chunk_index), ".csv", sep = ""), row.names=FALSE)
  }

  ## function to update the labelled data frame
  update_labelled_df <- function(chunk_index, execution_time = NA) {
    
    # read the newly labelled data
    newly_labelled_data <- read.csv(paste(local_path, get_file_name(chunk_index), ".csv", sep = ""))
    
    # only keep the COICOP columns and the index
    coicop_cols <- c(product_id_col_name, "coicop_modeled_1", "coicop_modeled_2", "coicop_modeled_3")

    # print the number of labels generated
    if (verbose) {
      print(paste(nrow(newly_labelled_data), "labels were generated out of", CHUNK_SIZE))
    }

    # read the existing labelled data
    if (file.exists(gpt_output_file)) {
      labelled_data <- read.csv(gpt_output_file)
      labelled_data <- predictions_to_numeric(labelled_data)
      newly_labelled_data <- predictions_to_numeric(newly_labelled_data)

      # combining existing and new labels
      newly_labelled_data <- rbind(
            labelled_data %>% select(all_of(coicop_cols)),
            newly_labelled_data %>% select(all_of(coicop_cols))
        )
    } else {
        newly_labelled_data <- newly_labelled_data %>% select(all_of(coicop_cols))
    }

    # reading the intermediary file (which has ALL original columns)
    intermediary_data <- read.csv(intermediary_file_path)
    
    # joining the COICOP classifications with the original data
    final_output <- intermediary_data %>%
        left_join(newly_labelled_data, by = product_id_col_name)
    
    # writing the final output to a CSV file
    write.csv(final_output, gpt_output_file, row.names = FALSE)
    }

  ## complete workflow of the coicop labeller
  products_to_label <- products

  # check if existing GPT output file exists
  if (file.exists(gpt_output_file)) {

    # only need this to remove rows that have already been labelled by GPT
    if (verbose) {
      print(paste("Existing full GPT output file exists at", gpt_output_file))
    }
    labelled_data <- read.csv(gpt_output_file) %>%
      select(all_of(product_id_col_name))

    # only process the rows that contain product codes not in the existing file
    products_to_label <- products[!(products[product_id_col_name] %in% labelled_data[product_id_col_name]), ] %>%
      select(all_of(c(product_id_col_name, product_col_name)))

  } else {
    if (verbose) {
      print(paste("No full GPT output file exists with the name: ", gpt_output_file,
                ". Creating new file with this name and location.",
                sep = ""))
    }
  }

  if (verbose) {
    print(paste("Out of", nrow(products), "products,", nrow(products_to_label),
                "labels will be generated. If the numbers differ, then there may
                have been some products that have already been labelled."))
  }

  ## function to convert a chunk of products to a string
  chunk_to_str <- function(chunk) {
    output_string <- apply(chunk, 1, function(row) {
      paste0(row[product_id_col_name], " ", row[product_col_name])
    })
    return(paste(output_string, collapse = "\n"))
  }

  # chunking the products
  products_to_label_chunked <- products_to_label %>%
    mutate(group_index = ceiling(row_number() / CHUNK_SIZE))

  # splitting the products into chunks
  products_to_label_chunked <- split(products_to_label_chunked,
                                     products_to_label_chunked$group_index)

  # processing each chunk
  for (chunk_index in names(products_to_label_chunked)) {
    if (verbose) {
      print(paste("Generating Labels for Chunk",
                  chunk_index, "of",
                  length(products_to_label_chunked),
                  "chunks of size", CHUNK_SIZE))
    }
    execution_time <- system.time(generate_labels(chunk_index,
                                                  products_to_label_chunked))
    gen_labels_to_csv(chunk_index)
    if (verbose) {
      print(paste("Execution Time: ", execution_time["elapsed"]))
    }
    if (verbose) {
      print(paste("Updating Files in existing DB for Chunk", chunk_index))
    }
    update_labelled_df(chunk_index, execution_time = execution_time["elapsed"])
  }
}

# running the labeling function
coicop_labeller(products, product_id_col_name, product_col_name)

# deleting 'intermediary_otherCols.csv' file from the directory
file.remove (intermediary_file_path)
