\name{print.terrio_layer}
\alias{print.terrio_layer}
\title{Print a terrio layer}
\usage{
\method{print}{terrio_layer}(x, ...)
}
\arguments{
\item{x}{A \code{terrio_layer} object.}
\item{...}{Passed to the data.frame print of the attribute columns.}
}
\description{
Shows the layer metadata and the first rows of the attribute columns. The
\code{geometry} column (a list of raw WKB) is summarized, not printed.
}
