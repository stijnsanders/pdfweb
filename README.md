# A PDF website
I noticed it's possible to have hyper-links in a PDF document\
and nowadays, PDF's open right in the same browser window.\
(Is it because JavaScript has gotten this strong?\
It's not only doable but just plain better security.)\
So I thought you could just as well have a dynamic website
with PDF (and PostScript) instead of HTML!

But what library or framework to use? (Other than [xxm](https://github.com/stijnsanders/xxm), that is.)\
Nààh, we're all into [rolling our own PDF's](https://www.adobe.com/devnet/pdf/pdf_reference.html). Because we can.\
Fonts in PDF/PostScript are still a bit of a mystery to me,\
but page objects like annotations with a link action are not.

This is a proof-of-concept only and (currently?) serves no other purpose.

_Try it out [here](http://yoy.be/home/pdfweb/)_