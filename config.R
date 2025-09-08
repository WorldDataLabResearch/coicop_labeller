if (!exists("OPEN_API_KEY")) {
  if (!file.exists("keys.R")) {
    stop("No OPEN_API_KEY exists and no file keys.R exists.")
  } else {
    source("keys.R")
  }
  if (!exists("OPEN_API_KEY") ||
      (exists("OPEN_API_KEY") &&
       OPEN_API_KEY == "")) {
    stop("No OPEN_API_KEY exists in keys.R")
  }
}

# -----------
# GPT Function Defaults
# -----------
verbose <- TRUE

systeminput <- paste("You are a classifier that needs to classify an inputted revenue stream description as one of many CoiCop labels. These CoiCop labels have 4 levels. For example, Food & Beverage is level 1, Food is level 2, Bread & Cereals is level 3, Cereals is level 4. The format of the label is x.x.x.x, with each x being a level.
                     Some products can appear in both “at home” and “outside home” consumption branches especially for food (e.g., coffee beans vs coffee in restaurants). Usually food appears first and then restaurants. Data files are often structured with parent categories first, followed by more specific (children) categories.
                     Dont add values especially for coicop_3 if they dont exist as a combination in the input examples.
                     If it is a general enough category, input 0s for each of the following level labels. The following is a string containing the entire labelling system: \n",
                     coicop_labels_str_stripped, "And the following are 10 examples of correctly labelled items: \n",
                     coicop_few_shot_examples)
CHUNK_SIZE <- 500

# the Open AI Model parameter needs to be in the Open AI Model
# format found here: https://platform.openai.com/docs/models/
OPEN_AI_MODEL <- "gpt-4o"
#OPEN_AI_MODEL <- "gpt-3.5-turbo"

# path and name of output file
gpt_output_file <- ""

# path to folder where all GPT files will be uploaded
local_path <- ""

# model can be anything that is a unique model
MODEL_SET <- Sys.Date()
