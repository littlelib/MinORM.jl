function typeto_snakecase_name(T::Type)
    raw_name=string(T)
    last_name=split(raw_name, ".")[end]
    name=last_name|>collect
    for (i,char) in enumerate(name)
        if isuppercase(char)==true
            name[i]=lowercase(char)
            if i!=1
                insert!(name, i, '_')
            end
        end
    end
    return join(name)
end



