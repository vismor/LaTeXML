**LaTeXML GIT Repository**

This repository is used to maintain the LaTeXML software used on vismor.com.

There are two active branches:

- NIST: periodically updated from the LaTeXML svn repository at nist.gov
- master: NIST merged with customizations for vismor.com.

**LaTeXML Functionality**

At vismor.com documents are maintained in Scrivener as MultiMarkdown. They are then compiled
into TeX files by Scrivener. The TeX files are converted to PDF documents and XHTML web
documents. LaTexML is used for the TeX-XHTML conversion. It is particularly adept at TeX
to MathML conversions.

To quote from the [LaTexML web site](http://dlmf.nist.gov/LaTeXML):

> In brief, latexml is a program, written in Perl, that attempts to faithfully mimic TeX’s behaviour, 
> but produces XML instead of dvi. The document model of the target XML makes explicit the model implied 
> by LaTeX. The processing and model are both extensible; you can define the mapping between TeX constructs 
> and the XML fragments to be created. A postprocessor, latexmlpost converts this XML into other formats 
> such as HTML or XHTML, with options to convert the math into MathML (currently only presentation) or 
> images.

Visit that site for more information.